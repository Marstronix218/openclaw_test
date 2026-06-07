# OpenClaw in Docker (local)

Runs the [OpenClaw](https://openclaw.ai) gateway and a local
[Qwen2.5-1.5B-Instruct](https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct) model
server **entirely inside a Docker container** on your machine. Nothing runs on
Daytona — the container has normal outbound internet, so **Weave (W&B) tracing
works out of the box**.

## Prerequisites

- Docker
- An LLM is bundled (Qwen 1.5B on CPU); no cloud API key required for inference
- Optional: `WANDB_API_KEY` for Weave tracing

## Setup

```bash
cp .env.example .env
# Fill in OPENCLAW_GATEWAY_TOKEN (openssl rand -hex 32)
# Optional: WANDB_API_KEY from https://wandb.ai/authorize

bash scripts/up.sh
```

`up.sh` runs `local-up.sh`, which:

1. Builds the image from `snapshot/Dockerfile` (Node 24, OpenClaw, CPU torch,
   transformers, Qwen weights).
2. Starts container `openclaw-local` with port `18789` mapped to localhost.
3. Onboards + starts the OpenClaw gateway.
4. Starts the Qwen OpenAI-compatible model server on `:8000` (Weave-traced when
   `WANDB_API_KEY` is set).
5. Wires OpenClaw to the local model and restarts the gateway.

First build downloads torch + model weights and can take a while.

## Tracing with Weave (Weights & Biases)

Every LLM call OpenClaw makes goes through `model-server/server.py`, where
Weave tracing is wired in. With `WANDB_API_KEY` set in `.env`, each turn's
prompt, completion, tool calls, and token usage show up in your Weave project.

```bash
# In .env:
WANDB_API_KEY=...                  # from https://wandb.ai/authorize
WEAVE_PROJECT=openclaw-sandbox     # or "entity/project"
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

Tracing is opt-in: if `WANDB_API_KEY` is unset the server runs with zero
overhead.

> **Why not Daytona?** Shared Daytona regions block outbound traffic to
> `api.wandb.ai` / `trace.wandb.ai`, so Weave cannot connect from inside a
> sandbox. A local Docker container has unrestricted egress. Legacy Daytona
> scripts (`20-sandbox.sh`, etc.) remain in `scripts/` if you need them for
> other reasons, but `up.sh` / `down.sh` / `status.sh` / `ssh.sh` all target
> Docker now.

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
openclaw agent --message "What can you do?" --thinking high
```

Gateway UI: `http://localhost:18789` (gated by `OPENCLAW_GATEWAY_TOKEN`).

## Notes

- The model runs on CPU inside the container. A full agent turn can take 1–2
  minutes; timeouts are raised to 1200s to accommodate this.
- CPU torch + model weights are baked into the image at build time.
- Secrets live only in `.env` (gitignored) and as container env vars.
