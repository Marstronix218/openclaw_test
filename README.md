# OpenClaw in Docker (local Qwen + Weave tracing)

Runs the [OpenClaw](https://openclaw.ai) gateway in Docker with a local
[Qwen2.5-1.5B-Instruct](https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct)
model server. Every LLM call is traced via
[Weave](https://wandb.ai/site/weave) when `WANDB_API_KEY` is set.

Designed for cloud VMs (e.g. NVIDIA Brev) with Docker — no Daytona or HF
Inference Providers required.

## Prerequisites

- Docker
- Outbound HTTPS (model download at build time; Weave traces at runtime)
- `WANDB_API_KEY` for tracing (optional but recommended)

## Setup

```bash
cp .env.example .env
# Fill in OPENCLAW_GATEWAY_TOKEN (openssl rand -hex 32)
# Fill in WANDB_API_KEY (https://wandb.ai/settings)

bash scripts/up.sh
```

`up.sh` runs `local-up.sh`, which:

1. Builds an image from `snapshot/Dockerfile` (Node 24 + OpenClaw + CPU torch + Qwen weights).
2. Starts container `openclaw-local` with port `18789` mapped to localhost.
3. Starts the Weave-traced Qwen model server on port `8000` inside the container.
4. Onboards OpenClaw and wires it to the local model server.
5. Starts the OpenClaw gateway.

First build downloads torch and model weights — can take several minutes.

## Day-to-day

```bash
bash scripts/status.sh       # container + gateway + model + weave status
bash scripts/ssh.sh          # interactive shell in the container
bash scripts/verify-model.sh # test a local completion (+ Weave trace)
bash scripts/down.sh         # stop & remove the container (image kept)
```

Talk to the assistant from inside the container:

```bash
bash scripts/ssh.sh
openclaw agent --message "What can you do?" --thinking high
```

Gateway UI: `http://localhost:18789` (gated by `OPENCLAW_GATEWAY_TOKEN`).

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `OPENCLAW_GATEWAY_TOKEN` | — | Gateway auth token (required) |
| `WANDB_API_KEY` | — | Weights & Biases API key (enables Weave tracing) |
| `WEAVE_PROJECT` | `openclaw-sandbox` | Weave project name |
| `MODEL_ID` | `Qwen/Qwen2.5-1.5B-Instruct` | Hugging Face model id |
| `OPENCLAW_CPU` | `4` | torch thread count (match VM vCPUs) |
| `LOCAL_IMAGE` | `openclaw-local` | Docker image name |
| `LOCAL_CONTAINER` | `openclaw-local` | Docker container name |

## NVIDIA Brev

Use **VM Mode + setup script** (Docker is preinstalled). Skip Jupyter.

1. Clone this repo on the instance.
2. Create `.env` with `OPENCLAW_GATEWAY_TOKEN` and `WANDB_API_KEY`.
3. Set `OPENCLAW_CPU` to match your instance vCPU count.
4. Run `bash scripts/up.sh`.
5. Expose port **18789** for the gateway.

## Notes

- Weave traces appear in your W&B project after the first model call.
- Secrets live only in `.env` (gitignored) and as container env vars.
- Legacy Daytona scripts remain in `scripts/` but are unused.
