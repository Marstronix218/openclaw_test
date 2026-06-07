# OpenClaw in Docker (Hugging Face + Weave tracing)

For the separate Brev `hyperstack_A100_80G` comparison using a locally
downloaded `Qwen/Qwen2.5-7B-Instruct` model, see [BREV.md](BREV.md). That path
uses vLLM on the Brev GPU, traces through an OpenAI-compatible Weave proxy,
and does not use Hugging Face Inference Providers.

Runs the [OpenClaw](https://openclaw.ai) gateway in Docker with a local
OpenAI-compatible proxy backed by
[`huggingface_hub.InferenceClient`](https://huggingface.co/docs/huggingface_hub/en/package_reference/inference_client).
Inference runs on your chosen
[Inference Provider](https://huggingface.co/docs/inference-providers) (default:
`featherless-ai`).

Every `InferenceClient.chat_completion` call is automatically traced in
[Weave](https://wandb.ai/site/weave) when `WANDB_API_KEY` is set, following the
[HF + Weave integration guide](https://docs.wandb.ai/weave/guides/integrations/huggingface).

## Prerequisites

- Docker
- `HF_TOKEN` with Inference Providers permission
- Optional: `WANDB_API_KEY` for Weave tracing

## Setup

```bash
cp .env.example .env
# Fill in OPENCLAW_GATEWAY_TOKEN (openssl rand -hex 32)
# Fill in HF_TOKEN from https://huggingface.co/settings/tokens
# Optional: WANDB_API_KEY from https://wandb.ai/authorize

bash scripts/up.sh
```

`up.sh` runs `local-up.sh`, which:

1. Builds a lightweight image (Node 24 + OpenClaw + huggingface_hub + weave).
2. Starts container `openclaw-local` with port `18789` mapped to localhost.
3. Starts the HF InferenceClient proxy on `:8000`.
4. Onboards OpenClaw and wires it to the proxy.
5. Starts the OpenClaw gateway.

## Tracing with Weave

The proxy calls `weave.init()` before creating `InferenceClient`, so Weave
autopatches and logs every inference call (inputs, outputs, chat view, metadata).

```bash
# In .env:
WANDB_API_KEY=...                  # from https://wandb.ai/authorize
WEAVE_PROJECT=openclaw-sandbox     # or "entity/project"
HF_TOKEN=hf_...                    # Inference Providers token
HF_MODEL_PROVIDER=featherless-ai   # or auto, together, groq, etc.
MODEL_ID=Qwen/Qwen2.5-1.5B-Instruct
```

After `bash scripts/up.sh`, check the model server log for your Weave URL:

```bash
bash scripts/status.sh
# or: docker exec openclaw-local grep "View Weave data at" /root/model-server/server.log
```

Run a test completion (shows up in Weave within a few seconds):

```bash
bash scripts/verify-model.sh
```

Tracing is opt-in: if `WANDB_API_KEY` is unset the server runs without Weave
overhead.

## Day-to-day

```bash
bash scripts/status.sh       # container + gateway + model + Weave URL
bash scripts/ssh.sh          # interactive shell in the container
bash scripts/verify-model.sh # test a model turn (and Weave trace)
bash scripts/down.sh         # stop & remove the container (image kept)
```

Talk to the assistant from inside the container:

```bash
bash scripts/ssh.sh
openclaw agent --agent main --message "What can you do?" --thinking high
```

Gateway UI: `http://localhost:18789` (gated by `OPENCLAW_GATEWAY_TOKEN`).

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `OPENCLAW_GATEWAY_TOKEN` | — | Gateway auth token (required) |
| `HF_TOKEN` | — | Hugging Face token with Inference Providers (required) |
| `HF_MODEL_PROVIDER` | `featherless-ai` | Inference provider for `InferenceClient` |
| `MODEL_ID` | `Qwen/Qwen2.5-1.5B-Instruct` | Model id on the Hub |
| `WANDB_API_KEY` | — | Weights & Biases API key (enables Weave tracing) |
| `WEAVE_PROJECT` | `openclaw-sandbox` | Weave project name |
| `LOCAL_IMAGE` | `openclaw-local` | Docker image name |
| `LOCAL_CONTAINER` | `openclaw-local` | Docker container name |

## Notes

- No local GPU/CPU model load — inference runs on the HF provider you select.
- Secrets live only in `.env` (gitignored) and as container env vars.
- Legacy Daytona scripts remain in `scripts/` but are unused by `up.sh`.
