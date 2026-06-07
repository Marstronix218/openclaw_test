# OpenClaw + local Qwen2.5-7B on Brev

This path is for the separate comparison box:

| Field | Value |
|---|---|
| Brev machine type | `hyperstack_A100_80G` |
| Provider | Hyperstack via Brev |
| GPU | 1x NVIDIA A100 80GB |
| Model | `Qwen/Qwen2.5-7B-Instruct` |
| Serving | Local vLLM, no Hugging Face Inference Provider |
| Tracing | W&B Weave through a local OpenAI-compatible proxy |
| OpenClaw | `2026.6.1` by default, configurable with `BREV_OPENCLAW_VERSION` |

The vLLM container downloads the model into `.brev-data/huggingface` on the
Brev host. Recreating the containers reuses those local weights.

## Start

On the Brev instance:

```bash
git switch feat/brev-qwen25-7b
cp .env.brev.example .env.brev
# Set OPENCLAW_GATEWAY_TOKEN. HF_TOKEN is optional for this public model.
# Set WANDB_API_KEY to send Qwen traces to WEAVE_PROJECT.

bash scripts/brev/up.sh
bash scripts/brev/verify.sh
bash scripts/brev/status.sh
```

The first run downloads the 7B model and takes longer. Later runs reuse the
host cache.

## Weave tracing

The OpenClaw model provider points to a proxy on `127.0.0.1:8001`. That proxy
uses the OpenAI SDK against the local vLLM server and initializes Weave before
serving requests. Normal and streaming completions therefore include prompts,
responses, tool calls, token usage, and latency in the configured project.

```bash
# In .env.brev:
WANDB_API_KEY=...
WEAVE_PROJECT=openclaw-qwen25-7b

bash scripts/brev/up.sh
bash scripts/brev/verify.sh
bash scripts/brev/status.sh
```

Tracing is disabled when `WANDB_API_KEY` is blank; inference still flows
through the same proxy. The proxy log is persisted at
`.brev-data/openclaw/weave-proxy.log`.

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

The setup uses `tools.profile=minimal` and widens it with `tools.alsoAllow`.
It intentionally leaves `tools.allow` unset because that additional policy is
intersected with the profile policy and can remove every callable tool. The
`process` and `apply_patch` helpers are explicitly denied to keep the final
surface at the six tools above.

Repair an existing persisted configuration without rebuilding the containers:

```bash
bash scripts/brev/repair-tools.sh
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
