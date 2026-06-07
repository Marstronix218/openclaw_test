"""OpenAI-compatible proxy for Hugging Face Inference Providers.

Routes /v1/chat/completions to huggingface_hub.InferenceClient. When
WANDB_API_KEY is set, weave.init() enables automatic tracing of every
InferenceClient call (see https://docs.wandb.ai/weave/guides/integrations/huggingface).
"""
import json
import os
import sys
import time
import traceback
import uuid
from typing import Any, Optional

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, StreamingResponse
from pydantic import BaseModel


def log(*a):
    print(*a, file=sys.stderr, flush=True)


# --- Weave (Weights & Biases) tracing ------------------------------------
# weave.init() must run before InferenceClient is used so Weave can autopatch
# chat_completion calls. See the HF integration guide.
WEAVE_ENABLED = False
weave = None  # type: ignore

if os.environ.get("WANDB_API_KEY"):
    try:
        import weave as _weave  # type: ignore

        weave = _weave
        _weave_project = os.environ.get("WEAVE_PROJECT", "openclaw-sandbox")
        weave.init(_weave_project)
        WEAVE_ENABLED = True
        log(f"[weave] tracing enabled -> project '{_weave_project}'")
    except Exception as e:  # pragma: no cover
        log(f"[weave] disabled (init failed: {e!r})")
else:
    log("[weave] disabled (set WANDB_API_KEY to enable tracing)")

# InferenceClient after weave.init so calls are auto-traced.
from huggingface_hub import InferenceClient  # noqa: E402

_hf_token = (
    os.environ.get("HF_TOKEN")
    or os.environ.get("HUGGINGFACE_TOKEN")
    or os.environ.get("HUGGINGFACE_HUB_TOKEN")
)
_provider = os.environ.get("HF_MODEL_PROVIDER", "featherless-ai")
MODEL_ID = os.environ.get("MODEL_ID", "Qwen/Qwen2.5-1.5B-Instruct")
DEFAULT_MAX_TOKENS = int(os.environ.get("MAX_NEW_TOKENS", "512"))

if not _hf_token:
    log("[server] ERROR: set HF_TOKEN (Hugging Face token with Inference Providers access)")
    sys.exit(1)

hf_client = InferenceClient(provider=_provider, token=_hf_token)
log(f"[server] InferenceClient ready (provider={_provider}, model={MODEL_ID})")

app = FastAPI()


@app.exception_handler(Exception)
async def _unhandled(request: Request, exc: Exception):
    tb = traceback.format_exc()
    log("[error]", tb)
    return JSONResponse(
        status_code=500,
        content={"error": {"message": str(exc), "type": type(exc).__name__, "traceback": tb}},
    )


class ChatRequest(BaseModel):
    model: Optional[str] = None
    messages: list[dict[str, Any]]
    tools: Optional[list[dict[str, Any]]] = None
    tool_choice: Optional[Any] = None
    temperature: Optional[float] = 0.7
    top_p: Optional[float] = 0.8
    max_tokens: Optional[int] = None
    stream: Optional[bool] = False


def _completion_kwargs(req: ChatRequest) -> dict[str, Any]:
    kwargs: dict[str, Any] = {
        "model": req.model or MODEL_ID,
        "messages": req.messages,
        "max_tokens": min(req.max_tokens or DEFAULT_MAX_TOKENS, DEFAULT_MAX_TOKENS),
    }
    if req.temperature is not None:
        kwargs["temperature"] = req.temperature
    if req.top_p is not None:
        kwargs["top_p"] = req.top_p
    if req.tools:
        kwargs["tools"] = req.tools
    if req.tool_choice is not None:
        kwargs["tool_choice"] = req.tool_choice
    return kwargs


def _tool_call_to_openai(tc: Any) -> dict[str, Any]:
    fn = getattr(tc, "function", None) or tc.get("function", {})
    name = getattr(fn, "name", None) or fn.get("name", "")
    args = getattr(fn, "arguments", None) or fn.get("arguments", "{}")
    if not isinstance(args, str):
        args = json.dumps(args)
    tc_id = getattr(tc, "id", None) or tc.get("id") or ("call_" + uuid.uuid4().hex[:24])
    return {
        "id": tc_id,
        "type": "function",
        "function": {"name": name, "arguments": args},
    }


def _message_to_openai(msg: Any) -> dict[str, Any]:
    content = getattr(msg, "content", None)
    tool_calls = getattr(msg, "tool_calls", None)
    out: dict[str, Any] = {"role": "assistant", "content": content}
    if tool_calls:
        out["tool_calls"] = [_tool_call_to_openai(tc) for tc in tool_calls]
    return out


def _usage_to_openai(usage: Any) -> dict[str, int]:
    if usage is None:
        return {"prompt_tokens": 0, "completion_tokens": 0, "total_tokens": 0}
    pt = getattr(usage, "prompt_tokens", None) or usage.get("prompt_tokens", 0)
    ct = getattr(usage, "completion_tokens", None) or usage.get("completion_tokens", 0)
    tt = getattr(usage, "total_tokens", None) or usage.get("total_tokens", pt + ct)
    return {"prompt_tokens": int(pt), "completion_tokens": int(ct), "total_tokens": int(tt)}


# weave.Model captures model config and versions each change (HF integration guide).
if WEAVE_ENABLED and weave is not None:

    class ChatModel(weave.Model):
        model_id: str = MODEL_ID
        provider: str = _provider
        default_max_tokens: int = DEFAULT_MAX_TOKENS

        @weave.op()
        def complete(self, messages: list, tools: list | None, params: dict) -> dict[str, Any]:
            kwargs = {"messages": messages, **params}
            if tools:
                kwargs["tools"] = tools
            response = hf_client.chat_completion(**kwargs)
            choice = response.choices[0]
            msg = _message_to_openai(choice.message)
            finish = getattr(choice, "finish_reason", None) or "stop"
            return {
                "message": msg,
                "finish_reason": finish,
                "usage": _usage_to_openai(getattr(response, "usage", None)),
            }

    _chat_model = ChatModel()

    def _complete(req: ChatRequest) -> dict[str, Any]:
        return _chat_model.complete(req.messages, req.tools, _completion_kwargs(req))

else:

    def _complete(req: ChatRequest) -> dict[str, Any]:
        response = hf_client.chat_completion(**_completion_kwargs(req))
        choice = response.choices[0]
        msg = _message_to_openai(choice.message)
        finish = getattr(choice, "finish_reason", None) or "stop"
        return {
            "message": msg,
            "finish_reason": finish,
            "usage": _usage_to_openai(getattr(response, "usage", None)),
        }


@app.get("/health")
def health():
    return {"status": "ok", "model": MODEL_ID, "provider": _provider}


@app.get("/v1/models")
def list_models():
    return {
        "object": "list",
        "data": [{"id": MODEL_ID, "object": "model", "created": int(time.time()), "owned_by": _provider}],
    }


@app.post("/v1/chat/completions")
def chat_completions(req: ChatRequest):
    cmpl_id = "chatcmpl-" + uuid.uuid4().hex
    created = int(time.time())

    if req.stream:
        return StreamingResponse(_stream(req, cmpl_id, created), media_type="text/event-stream")

    result = _complete(req)
    return JSONResponse({
        "id": cmpl_id,
        "object": "chat.completion",
        "created": created,
        "model": req.model or MODEL_ID,
        "choices": [{"index": 0, "message": result["message"], "finish_reason": result["finish_reason"]}],
        "usage": result["usage"],
    })


def _sse(obj: dict[str, Any]) -> str:
    return f"data: {json.dumps(obj)}\n\n"


def _stream(req: ChatRequest, cmpl_id: str, created: int):
    base = {"id": cmpl_id, "object": "chat.completion.chunk", "created": created, "model": req.model or MODEL_ID}
    yield _sse({**base, "choices": [{"index": 0, "delta": {"role": "assistant"}, "finish_reason": None}]})

    kwargs = _completion_kwargs(req)
    kwargs["stream"] = True
    finish_reason = "stop"

    try:
        for chunk in hf_client.chat_completion(**kwargs):
            for choice in chunk.choices:
                delta = choice.delta
                content = getattr(delta, "content", None)
                tool_calls = getattr(delta, "tool_calls", None)
                fr = getattr(choice, "finish_reason", None)
                if fr:
                    finish_reason = fr

                delta_out: dict[str, Any] = {}
                if content:
                    delta_out["content"] = content
                if tool_calls:
                    delta_out["tool_calls"] = [
                        {
                            "index": getattr(tc, "index", i),
                            "id": getattr(tc, "id", None),
                            "type": getattr(tc, "type", "function"),
                            "function": {
                                "name": getattr(getattr(tc, "function", None), "name", ""),
                                "arguments": getattr(getattr(tc, "function", None), "arguments", ""),
                            },
                        }
                        for i, tc in enumerate(tool_calls)
                    ]
                if delta_out:
                    yield _sse({**base, "choices": [{"index": 0, "delta": delta_out, "finish_reason": None}]})
    except Exception as e:
        log("[stream error]", e)
        raise

    yield _sse({**base, "choices": [{"index": 0, "delta": {}, "finish_reason": finish_reason}]})
    yield "data: [DONE]\n\n"


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=int(os.environ.get("PORT", "8000")), log_level="info")
