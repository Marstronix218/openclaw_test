# OpenClaw + local Qwen2.5-7B on Brev

This path is for the separate comparison box:

| Field | Value |
|---|---|
| Brev machine type | `hyperstack_A100_80G` |
| Provider | Hyperstack via Brev |
| GPU | 1x NVIDIA A100 80GB |
| Model | `Qwen/Qwen2.5-7B-Instruct` |
| Serving | Local vLLM, no Hugging Face Inference Provider |

The vLLM container downloads the model into `.brev-data/huggingface` on the
Brev host. Recreating the containers reuses those local weights.

## Start

On the Brev instance:

```bash
git switch feat/brev-qwen25-7b
cp .env.brev.example .env.brev
# Set OPENCLAW_GATEWAY_TOKEN. HF_TOKEN is optional for this public model.

bash scripts/brev/up.sh
bash scripts/brev/verify.sh
bash scripts/brev/status.sh
```

The first run downloads the 7B model and takes longer. Later runs reuse the
host cache.

From your laptop, forward the private gateway port:

```bash
brev port-forward <instance-name> --port 18789:18789
```

Then open `http://localhost:18789` and enter `OPENCLAW_GATEWAY_TOKEN`.

## Comparison controls

The configured tool surface has six tools:

```text
session_status, web_search, web_fetch, read, write, exec
```

`BRAVE_API_KEY` is optional but required for OpenClaw `web_search`.
The bundled `weather` skill is the only bundled skill enabled.

Live web revoke:

```bash
bash scripts/brev/web-policy.sh allow
bash scripts/brev/web-policy.sh deny
```

Exec approval policy:

```bash
bash scripts/brev/approval-mode.sh full
bash scripts/brev/approval-mode.sh strict
```

`strict` uses allowlist + ask-on-miss with deny fallback. Use the Control UI
when you want to approve scenario 6 manually. CLI-only runs record a denial
when no approval UI handles the request.

## Run benchmark scenarios

Run scenarios in order so the `alice` session is preserved:

```bash
bash scripts/brev/run-scenario.sh 1
bash scripts/brev/run-scenario.sh 2
bash scripts/brev/run-scenario.sh 3
bash scripts/brev/run-scenario.sh 4a
bash scripts/brev/run-scenario.sh 4b
bash scripts/brev/run-scenario.sh 5
bash scripts/brev/run-scenario.sh 6
bash scripts/brev/run-scenario.sh 7
```

Each run writes prompt, response, policy, GPU, gateway, and vLLM artifacts
under `.brev-data/runs`.

Export a redacted bundle:

```bash
bash scripts/brev/export-artifacts.sh
```

The archive is written under `artifacts/`.

## Stop

```bash
bash scripts/brev/down.sh
```

This removes only the containers and network. Delete `.brev-data` separately
only when you also want to remove downloaded model weights and OpenClaw state.
