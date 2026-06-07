"""Minimal OpenAI-compatible server for Qwen/Qwen2.5-1.5B-Instruct on CPU.

Exposes /v1/models and /v1/chat/completions (streaming + non-streaming) backed
by HuggingFace transformers. Tool calls are parsed from Qwen's Hermes-style
<tool_call>{...}</tool_call> blocks into OpenAI `tool_calls`.
"""
import json
import os
import re
import sys
import time
import traceback
import uuid
from threading import Thread
from typing import Any, Optional

import torch
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, StreamingResponse
from pydantic import BaseModel
from transformers import AutoModelForCausalLM, AutoTokenizer, TextIteratorStreamer


def log(*a):
    print(*a, file=sys.stderr, flush=True)


# --- Weave (Weights & Biases) tracing ------------------------------------
# Every LLM call OpenClaw makes flows through this server, so this is the
# natural place to capture prompts/completions/tool-calls/usage. Enabled when
# a WANDB_API_KEY is present; otherwise this is a no-op so the server still
# runs on snapshots that don't have weave installed.
WEAVE_ENABLED = False
if os.environ.get("WANDB_API_KEY"):
    try:
        import weave  # type: ignore

        _weave_project = os.environ.get("WEAVE_PROJECT", "openclaw-sandbox")
        weave.init(_weave_project)
        WEAVE_ENABLED = True
        log(f"[weave] tracing enabled -> project '{_weave_project}'")
    except Exception as e:  # pragma: no cover - best-effort observability
        log(f"[weave] disabled (init failed: {e!r}). "
            "Install with `pip install weave` / rebuild the snapshot to trace.")
else:
    log("[weave] disabled (set WANDB_API_KEY to enable tracing)")


def maybe_op(name: Optional[str] = None):
    """Decorate with `weave.op` only when tracing is enabled; otherwise return
    the function untouched so the server has zero overhead/deps without W&B."""
    def deco(fn):
        if not WEAVE_ENABLED:
            return fn
        return weave.op(name=name)(fn) if name else weave.op()(fn)
    return deco


MODEL_ID = os.environ.get("MODEL_ID", "Qwen/Qwen2.5-1.5B-Instruct")
DTYPE = os.environ.get("DTYPE", "bfloat16")
NUM_THREADS = int(os.environ.get("NUM_THREADS", str(os.cpu_count() or 4)))
DEFAULT_MAX_NEW_TOKENS = int(os.environ.get("MAX_NEW_TOKENS", "1024"))

torch.set_num_threads(NUM_THREADS)
_dtype = {"bfloat16": torch.bfloat16, "float16": torch.float16, "float32": torch.float32}.get(DTYPE, torch.bfloat16)

print(f"[server] loading {MODEL_ID} (dtype={DTYPE}, threads={NUM_THREADS}) ...", flush=True)
tokenizer = AutoTokenizer.from_pretrained(MODEL_ID)
model = AutoModelForCausalLM.from_pretrained(
    MODEL_ID,
    torch_dtype=_dtype,
    low_cpu_mem_usage=True,
)
model.eval()
print("[server] model ready", flush=True)

app = FastAPI()


@app.exception_handler(Exception)
async def _unhandled(request: Request, exc: Exception):
    tb = traceback.format_exc()
    log("[error]", tb)
    return JSONResponse(status_code=500, content={"error": {"message": str(exc), "type": type(exc).__name__, "traceback": tb}})

TOOL_CALL_RE = re.compile(r"<tool_call>\s*(\{.*?\})\s*</tool_call>", re.DOTALL)


class ChatRequest(BaseModel):
    model: Optional[str] = None
    messages: list[dict[str, Any]]
    tools: Optional[list[dict[str, Any]]] = None
    tool_choice: Optional[Any] = None
    temperature: Optional[float] = 0.7
    top_p: Optional[float] = 0.8
    max_tokens: Optional[int] = None
    stream: Optional[bool] = False


def _normalize_messages(messages: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Flatten OpenAI-style structured content (list of {type,text}) into the
    plain strings Qwen's chat template expects."""
    out = []
    for m in messages:
        m = dict(m)
        c = m.get("content")
        if isinstance(c, list):
            parts = []
            for block in c:
                if isinstance(block, dict):
                    parts.append(block.get("text") or block.get("content") or "")
                else:
                    parts.append(str(block))
            m["content"] = "\n".join(p for p in parts if p)
        elif c is None:
            m["content"] = ""
        out.append(m)
    return out


def _build_inputs(req: ChatRequest):
    kwargs: dict[str, Any] = {"tokenize": False, "add_generation_prompt": True}
    if req.tools:
        kwargs["tools"] = req.tools
    messages = _normalize_messages(req.messages)
    text = tokenizer.apply_chat_template(messages, **kwargs)
    return tokenizer(text, return_tensors="pt")


def _gen_kwargs(req: ChatRequest, inputs) -> dict[str, Any]:
    # Hard-cap output so a slow CPU turn stays within OpenClaw's timeout.
    max_new = min(req.max_tokens or DEFAULT_MAX_NEW_TOKENS, DEFAULT_MAX_NEW_TOKENS)
    temp = req.temperature if req.temperature is not None else 0.7
    do_sample = temp > 0
    g: dict[str, Any] = {
        **inputs,
        "max_new_tokens": max_new,
        "do_sample": do_sample,
        "pad_token_id": tokenizer.pad_token_id or tokenizer.eos_token_id,
    }
    if do_sample:
        g["temperature"] = temp
        g["top_p"] = req.top_p if req.top_p is not None else 0.8
    return g


def _parse_tool_calls(text: str):
    calls = []
    for m in TOOL_CALL_RE.finditer(text):
        try:
            obj = json.loads(m.group(1))
        except json.JSONDecodeError:
            continue
        args = obj.get("arguments", {})
        calls.append({
            "id": "call_" + uuid.uuid4().hex[:24],
            "type": "function",
            "function": {
                "name": obj.get("name", ""),
                "arguments": json.dumps(args) if not isinstance(args, str) else args,
            },
        })
    content = TOOL_CALL_RE.sub("", text).strip()
    return content, calls


@app.get("/health")
def health():
    return {"status": "ok", "model": MODEL_ID}


@app.get("/v1/models")
def list_models():
    return {
        "object": "list",
        "data": [{"id": MODEL_ID, "object": "model", "created": int(time.time()), "owned_by": "local"}],
    }


@maybe_op(name="qwen_chat_completion")
def _complete(req: ChatRequest, inputs, prompt_tokens: int) -> dict[str, Any]:
    """Run a non-streaming generation. Wrapped in a Weave op so each turn shows
    up as a trace with its inputs (messages/tools/params) and outputs
    (content/tool_calls/usage)."""
    with torch.no_grad():
        out = model.generate(**_gen_kwargs(req, inputs))
    gen = out[0][prompt_tokens:]
    text = tokenizer.decode(gen, skip_special_tokens=True)
    content, tool_calls = _parse_tool_calls(text)
    completion_tokens = int(gen.shape[-1])
    return {
        "content": content,
        "tool_calls": tool_calls,
        "finish_reason": "tool_calls" if tool_calls else "stop",
        "usage": {
            "prompt_tokens": prompt_tokens,
            "completion_tokens": completion_tokens,
            "total_tokens": prompt_tokens + completion_tokens,
        },
    }


@maybe_op(name="qwen_chat_completion_stream")
def _record_stream(req: ChatRequest, content: Optional[str], tool_calls: list, usage: dict) -> dict[str, Any]:
    """Record the assembled result of a streamed turn so it appears in Weave
    alongside non-streamed turns (the op's return value is what gets logged)."""
    return {
        "content": content,
        "tool_calls": tool_calls,
        "finish_reason": "tool_calls" if tool_calls else "stop",
        "usage": usage,
    }


@app.post("/v1/chat/completions")
def chat_completions(req: ChatRequest):
    inputs = _build_inputs(req)
    prompt_tokens = int(inputs["input_ids"].shape[-1])
    cmpl_id = "chatcmpl-" + uuid.uuid4().hex
    created = int(time.time())

    if req.stream:
        return StreamingResponse(_stream(req, inputs, cmpl_id, created, prompt_tokens), media_type="text/event-stream")

    result = _complete(req, inputs, prompt_tokens)
    content = result["content"]
    tool_calls = result["tool_calls"]

    message: dict[str, Any] = {"role": "assistant", "content": content or None}
    if tool_calls:
        message["tool_calls"] = tool_calls

    return JSONResponse({
        "id": cmpl_id,
        "object": "chat.completion",
        "created": created,
        "model": MODEL_ID,
        "choices": [{"index": 0, "message": message, "finish_reason": result["finish_reason"]}],
        "usage": result["usage"],
    })


def _sse(obj: dict[str, Any]) -> str:
    return f"data: {json.dumps(obj)}\n\n"


def _usage(prompt_tokens: int, full: str) -> dict[str, int]:
    completion_tokens = len(tokenizer(full, add_special_tokens=False)["input_ids"])
    return {
        "prompt_tokens": prompt_tokens,
        "completion_tokens": completion_tokens,
        "total_tokens": prompt_tokens + completion_tokens,
    }


def _stream(req: ChatRequest, inputs, cmpl_id: str, created: int, prompt_tokens: int):
    """Stream plain text token-by-token; if tool calls are detected, buffer the
    whole output and emit tool_calls in the final delta instead of content."""
    base = {"id": cmpl_id, "object": "chat.completion.chunk", "created": created, "model": MODEL_ID}

    yield _sse({**base, "choices": [{"index": 0, "delta": {"role": "assistant"}, "finish_reason": None}]})

    streamer = TextIteratorStreamer(tokenizer, skip_prompt=True, skip_special_tokens=True)
    gk = _gen_kwargs(req, inputs)
    gk["streamer"] = streamer
    thread = Thread(target=lambda: model.generate(**gk))
    thread.start()

    full = ""
    saw_tool = False
    for piece in streamer:
        full += piece
        if "<tool_call>" in full:
            saw_tool = True
            continue  # hold back; emit tool_calls at the end
        if not saw_tool and piece:
            yield _sse({**base, "choices": [{"index": 0, "delta": {"content": piece}, "finish_reason": None}]})
    thread.join()

    if saw_tool:
        content, tool_calls = _parse_tool_calls(full)
        if tool_calls:
            _record_stream(req, content or None, tool_calls, _usage(prompt_tokens, full))
            deltas = []
            for i, tc in enumerate(tool_calls):
                deltas.append({"index": i, "id": tc["id"], "type": "function", "function": tc["function"]})
            yield _sse({**base, "choices": [{"index": 0, "delta": {"tool_calls": deltas}, "finish_reason": None}]})
            yield _sse({**base, "choices": [{"index": 0, "delta": {}, "finish_reason": "tool_calls"}]})
            yield "data: [DONE]\n\n"
            return

    _record_stream(req, full, [], _usage(prompt_tokens, full))
    yield _sse({**base, "choices": [{"index": 0, "delta": {}, "finish_reason": "stop"}]})
    yield "data: [DONE]\n\n"


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=int(os.environ.get("PORT", "8000")), log_level="info")
