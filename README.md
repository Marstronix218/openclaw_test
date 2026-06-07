# OpenClaw in Docker (Hugging Face + Weave tracing)

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

## Run on NVIDIA Brev

This configuration runs on Brev, but it does **not** use the Brev GPU.
Model inference is sent to the configured Hugging Face Inference Provider.
Use a CPU instance when available, or the least expensive GPU instance, unless
you plan to replace the proxy with a local GPU model server.

1. In the Brev console, create an instance in **VM Mode** and select the
   least expensive suitable instance type. Docker is preinstalled in this
   mode. Then connect from your local machine:

   ```bash
   brev login
   brev refresh
   brev shell openclaw-brev
   ```

2. In the Brev shell, keep the repository in the persistent workspace:

   ```bash
   cd /home/ubuntu/workspace
   git clone https://github.com/Marstronix218/openclaw_test.git
   cd openclaw_test
   cp .env.brev.example .env
   ```

3. Edit `.env` and set at least:

   ```dotenv
   OPENCLAW_GATEWAY_TOKEN=<output of: openssl rand -hex 32>
   HF_TOKEN=hf_...
   ```

   `WANDB_API_KEY` is optional. Then start and verify the service:

   ```bash
   bash scripts/up.sh
   bash scripts/status.sh
   bash scripts/verify-model.sh
   ```

4. On your local machine, keep this command running:

   ```bash
   brev port-forward openclaw-brev --port 18789:18789
   ```

   Open `http://localhost:18789` and authenticate with the
   `OPENCLAW_GATEWAY_TOKEN` from the Brev instance's `.env`.

Alternatively, add port `18789` under **Using Tunnels** in the Brev console for
a browser-accessible URL. Brev tunnels require browser authentication; CLI
port forwarding is simpler for local access.

Stop the application before stopping the Brev instance:

```bash
bash scripts/down.sh
```

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
