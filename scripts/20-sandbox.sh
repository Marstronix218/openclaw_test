#!/usr/bin/env bash
# Create the sandbox from the snapshot with maximum resources and a public
# preview for the gateway UI. Network access is left enabled (not blocked).
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require OPENCLAW_GATEWAY_TOKEN

# NOTE: resources (cpu/memory/disk) are baked into the snapshot (4/8/10) and
# inherited by the sandbox. Daytona rejects resource flags alongside --snapshot.

# Provider key is optional: you'll configure the model/auth interactively via
# `openclaw onboard`. If ANTHROPIC_API_KEY (or another) is set in .env, pass it
# through so the wizard can pick it up automatically.
extra_env=()
[[ -n "${ANTHROPIC_API_KEY:-}" ]] && extra_env+=(--env "ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY")
[[ -n "${OPENAI_API_KEY:-}" ]] && extra_env+=(--env "OPENAI_API_KEY=$OPENAI_API_KEY")

# Weave (W&B) tracing for the in-sandbox model server, when configured.
[[ -n "${WANDB_API_KEY:-}" ]] && extra_env+=(--env "WANDB_API_KEY=$WANDB_API_KEY")
[[ -n "${WEAVE_PROJECT:-}" ]] && extra_env+=(--env "WEAVE_PROJECT=$WEAVE_PROJECT")

echo "Creating sandbox '$SANDBOX_NAME' from snapshot '$SNAPSHOT_NAME' (inherits 4 vCPU / ${OPENCLAW_MEMORY_GB} GiB / ${OPENCLAW_DISK_GB} GiB)"
"$DAYTONA" create \
  --name "$SANDBOX_NAME" \
  --snapshot "$SNAPSHOT_NAME" \
  --target "$DAYTONA_TARGET" \
  --public \
  --auto-stop 0 \
  --env "HOME=/root" \
  --env "TERM=xterm-256color" \
  --env "OPENCLAW_GATEWAY_TOKEN=$OPENCLAW_GATEWAY_TOKEN" \
  "${extra_env[@]}"

echo "Sandbox info:"
"$DAYTONA" info "$SANDBOX_NAME"
