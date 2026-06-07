"""OpenAI-compatible tracing proxy for the local Brev vLLM server."""

import os
import sys
import traceback
from typing import Any

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, StreamingResponse


def log(*args: Any) -> None:
    print(*args, file=sys.stderr, flush=True)


WEAVE_ENABLED = False
WEAVE_PROJECT = os.environ.get("WEAVE_PROJECT", "openclaw-qwen25-7b")

if os.environ.get("WANDB_API_KEY"):
    try:
        import weave

        weave.init(WEAVE_PROJECT)
        WEAVE_ENABLED = True
        log(f"[weave] tracing enabled -> project '{WEAVE_PROJECT}'")
    except Exception as exc:  # pragma: no cover - startup integration failure
        log(f"[weave] tracing disabled (init failed: {exc!r})")
else:
    log("[weave] tracing disabled (set WANDB_API_KEY to enable)")

# Weave patches the OpenAI SDK after weave.init(), including streaming calls.
from openai import OpenAI  # noqa: E402


MODEL_ID = os.environ.get("MODEL_ID", "Qwen/Qwen2.5-7B-Instruct")
VLLM_BASE_URL = os.environ.get("VLLM_BASE_URL", "http://vllm-brev-qwen25-7b:8000/v1")
VLLM_API_KEY = os.environ.get("VLLM_API_KEY", "local")
REQUEST_TIMEOUT_SECONDS = float(os.environ.get("MODEL_TIMEOUT_SECONDS", "1200"))

client = OpenAI(
    base_url=VLLM_BASE_URL,
    api_key=VLLM_API_KEY,
    timeout=REQUEST_TIMEOUT_SECONDS,
)
app = FastAPI()

log(
    f"[proxy] ready (upstream={VLLM_BASE_URL}, model={MODEL_ID}, "
    f"weave={'on' if WEAVE_ENABLED else 'off'})"
)


@app.exception_handler(Exception)
async def unhandled_exception(request: Request, exc: Exception) -> JSONResponse:
    log("[error]", "".join(traceback.format_exception(type(exc), exc, exc.__traceback__)))
    return JSONResponse(
        status_code=500,
        content={"error": {"message": str(exc), "type": type(exc).__name__}},
    )


@app.get("/health")
def health() -> dict[str, Any]:
    return {
        "status": "ok",
        "model": MODEL_ID,
        "upstream": VLLM_BASE_URL,
        "weave_enabled": WEAVE_ENABLED,
        "weave_project": WEAVE_PROJECT if WEAVE_ENABLED else None,
    }


@app.get("/v1/models")
def list_models() -> JSONResponse:
    response = client.models.list()
    return JSONResponse(response.model_dump(mode="json", exclude_none=True))


def stream_completion(payload: dict[str, Any]):
    stream = client.chat.completions.create(**payload)
    try:
        for chunk in stream:
            yield f"data: {chunk.model_dump_json(exclude_none=True)}\n\n"
    finally:
        stream.close()
    yield "data: [DONE]\n\n"


@app.post("/v1/chat/completions")
def chat_completions(payload: dict[str, Any]):
    payload = dict(payload)
    payload.setdefault("model", MODEL_ID)
    stream = bool(payload.get("stream"))

    if stream:
        return StreamingResponse(
            stream_completion(payload),
            media_type="text/event-stream",
            headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
        )

    response = client.chat.completions.create(**payload)
    return JSONResponse(response.model_dump(mode="json", exclude_none=True))


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        app,
        host="0.0.0.0",
        port=int(os.environ.get("WEAVE_PROXY_PORT", "8001")),
        log_level="info",
    )
