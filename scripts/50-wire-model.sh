#!/usr/bin/env bash
# Register the local Qwen server as a custom OpenAI-compatible provider in
# OpenClaw, select it as the default model, and restart the gateway.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

: "${MODEL_ID:=Qwen/Qwen2.5-1.5B-Instruct}"
: "${MODEL_PORT:=8000}"

remote=$(cat <<REMOTE
set -e
export HOME=/root
unset OPENCLAW_HOME

# Register custom provider + model (idempotent: onboard merges).
openclaw onboard \
  --non-interactive --accept-risk \
  --mode local --flow manual \
  --auth-choice custom-api-key \
  --custom-base-url http://127.0.0.1:${MODEL_PORT}/v1 \
  --custom-model-id '$MODEL_ID' \
  --custom-compatibility openai \
  --custom-api-key local \
  --custom-text-input \
  --gateway-auth token --gateway-token-ref-env OPENCLAW_GATEWAY_TOKEN \
  --gateway-bind lan --gateway-port 18789 \
  --skip-daemon --skip-channels --skip-skills --skip-search --skip-hooks --skip-ui

echo "=== models after onboard ==="
openclaw models list 2>&1 | grep -v '^declare' || true

# Ensure the Qwen model is the default (derive its id from the list).
qwen_id=\$(openclaw models list 2>/dev/null | grep -i qwen | awk '{print \$1}' | head -1)
if [ -n "\$qwen_id" ]; then
  echo "Setting default model to: \$qwen_id"
  openclaw models set "\$qwen_id" || true
  # Provider id is the segment before the first '/'.
  prov=\${qwen_id%%/*}
  # A 1.5B model on CPU is slow; raise both the agent run timeout and the
  # per-provider idle timeout (prefill of the agent prompt can take minutes).
  openclaw config set "models.providers.\$prov.timeoutSeconds" 1200 || true
fi
openclaw config set agents.defaults.timeoutSeconds 1200 || true

echo "=== final model status ==="
openclaw models status 2>&1 | grep -v '^declare' || true

# Restart gateway (clean env) so the new model + timeouts apply. The image has
# no lsof/fuser, so use the supervised stop rather than --force.
openclaw gateway stop 2>/dev/null || true
sleep 3
: > /root/.openclaw/gateway.log
setsid bash -c 'openclaw gateway --bind lan --port 18789 >> /root/.openclaw/gateway.log 2>&1' < /dev/null &
sleep 6
echo "=== gateway.log tail ==="
tail -n 12 /root/.openclaw/gateway.log 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' || true
REMOTE
)

# Gateway is a long-lived child; run detached locally so we don't hang.
"$DAYTONA" exec "$SANDBOX_NAME" -- bash -lc "$remote" &
exec_pid=$!
sleep 30
kill "$exec_pid" 2>/dev/null || true
echo "Done wiring. Use scripts/verify-model.sh to test a turn."
