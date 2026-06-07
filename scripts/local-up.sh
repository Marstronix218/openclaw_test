#!/usr/bin/env bash
# Run OpenClaw + HF InferenceClient proxy (+ Weave tracing) in Docker.
#
# The model server uses huggingface_hub.InferenceClient. With WANDB_API_KEY set,
# weave.init() enables automatic tracing per:
# https://docs.wandb.ai/weave/guides/integrations/huggingface
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require OPENCLAW_GATEWAY_TOKEN
require HF_TOKEN

IMAGE="${LOCAL_IMAGE:-openclaw-local}"
CONTAINER="${LOCAL_CONTAINER:-openclaw-local}"
HOST_PORT="${OPENCLAW_PORT:-18789}"

dexec() { docker exec "$CONTAINER" bash -lc "$1"; }

echo "==> Building image '$IMAGE'"
docker build -t "$IMAGE" -f "$ROOT_DIR/snapshot/Dockerfile" "$ROOT_DIR/snapshot"

echo "==> (Re)creating container '$CONTAINER'"
docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
run_env=(
  -e HOME=/root -e TERM=xterm-256color
  -e "OPENCLAW_GATEWAY_TOKEN=$OPENCLAW_GATEWAY_TOKEN"
  -e "HF_TOKEN=$HF_TOKEN"
  -e "HUGGINGFACE_HUB_TOKEN=$HF_TOKEN"
  -e "HF_MODEL_PROVIDER=$HF_MODEL_PROVIDER"
  -e "MODEL_ID=$MODEL_ID"
  -e "WEAVE_PROJECT=$WEAVE_PROJECT"
)
[[ -n "${WANDB_API_KEY:-}" ]] && run_env+=(-e "WANDB_API_KEY=$WANDB_API_KEY")
[[ -n "${ANTHROPIC_API_KEY:-}" ]] && run_env+=(-e "ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY")
[[ -n "${OPENAI_API_KEY:-}" ]] && run_env+=(-e "OPENAI_API_KEY=$OPENAI_API_KEY")

docker run -d --name "$CONTAINER" -p "${HOST_PORT}:18789" "${run_env[@]}" "$IMAGE"

dexec 'mkdir -p /root/model-server'
docker cp "$ROOT_DIR/model-server/server.py" "$CONTAINER:/root/model-server/server.py"

echo "==> Onboarding + starting the OpenClaw gateway"
dexec "
set -e
export HOME=/root; unset OPENCLAW_HOME
mkdir -p /root/.openclaw/workspace
if [ ! -f /root/.openclaw/openclaw.json ]; then
  openclaw onboard --non-interactive --accept-risk --mode local --flow manual \
    --auth-choice skip \
    --gateway-auth token --gateway-token-ref-env OPENCLAW_GATEWAY_TOKEN \
    --gateway-bind lan --gateway-port 18789 \
    --skip-daemon --skip-channels --skip-skills --skip-search --skip-hooks --skip-ui --skip-health
fi
"

if [[ -n "${WANDB_API_KEY:-}" ]]; then
  weave_status="ENABLED (project: ${WEAVE_PROJECT})"
  weave_tracing=on
else
  weave_status="disabled — set WANDB_API_KEY in .env"
  weave_tracing=off
fi
echo "==> Starting HF InferenceClient proxy (Weave: ${weave_status}, provider: ${HF_MODEL_PROVIDER})"
dexec "
set -e
export HOME=/root; unset OPENCLAW_HOME
python3 -c 'import huggingface_hub, weave' || { echo 'image missing huggingface_hub/weave' >&2; exit 1; }
pkill -f 'model-server/server.py' 2>/dev/null || true
sleep 1
cd /root/model-server
PYTHONUNBUFFERED=1 \
  HF_TOKEN='${HF_TOKEN}' HUGGINGFACE_HUB_TOKEN='${HF_TOKEN}' \
  HF_MODEL_PROVIDER='${HF_MODEL_PROVIDER}' MODEL_ID='${MODEL_ID}' PORT='${MODEL_PORT}' \
  MAX_NEW_TOKENS='${MODEL_MAX_NEW_TOKENS:-512}' \
  WANDB_API_KEY='${WANDB_API_KEY:-}' WEAVE_PROJECT='${WEAVE_PROJECT}' \
  setsid bash -c 'python3 /root/model-server/server.py >> /root/model-server/server.log 2>&1' < /dev/null &
"

echo "==> Waiting for model server..."
for i in $(seq 1 30); do
  code=$(dexec "curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:${MODEL_PORT}/health" 2>/dev/null | tr -dc '0-9')
  if [ "$code" = "200" ]; then echo "    model server UP"; break; fi
  sleep 2
done

echo "==> Wiring OpenClaw to the local proxy"
dexec "
set -e
export HOME=/root; unset OPENCLAW_HOME
openclaw onboard --non-interactive --accept-risk --mode local --flow manual \
  --auth-choice custom-api-key \
  --custom-base-url http://127.0.0.1:${MODEL_PORT}/v1 \
  --custom-model-id '$MODEL_ID' --custom-compatibility openai \
  --custom-api-key local --custom-text-input \
  --gateway-auth token --gateway-token-ref-env OPENCLAW_GATEWAY_TOKEN \
  --gateway-bind lan --gateway-port 18789 \
  --skip-daemon --skip-channels --skip-skills --skip-search --skip-hooks --skip-ui --skip-health
openclaw models set \"custom-127-0-0-1-8000/${MODEL_ID}\" || true
openclaw config set agents.defaults.timeoutSeconds 1200 || true
openclaw config set tools.allow '[\"read\",\"write\",\"edit\",\"web_search\",\"web_fetch\",\"bash\"]' --strict-json || true
openclaw config set tools.deny '[]' --strict-json || true
openclaw config set skills.allowBundled '[\"weather\"]' --strict-json || true
openclaw config set web.search_backend duckduckgo || true
openclaw config set gateway.controlUi.allowedOrigins '[\"http://localhost:${HOST_PORT}\",\"http://127.0.0.1:${HOST_PORT}\"]' --strict-json || true
pkill -f 'openclaw gateway' 2>/dev/null || true
sleep 2
setsid bash -c 'openclaw gateway --bind lan --port 18789 --force >> /root/.openclaw/gateway.log 2>&1' < /dev/null &
sleep 5
"

echo
echo "Done. OpenClaw gateway: http://localhost:${HOST_PORT}  (token: \$OPENCLAW_GATEWAY_TOKEN)"
echo "HF provider:             ${HF_MODEL_PROVIDER}  model: ${MODEL_ID}"
echo "Weave project:         ${WEAVE_PROJECT}  (tracing: ${weave_tracing})"
echo "Verify a turn:         bash scripts/verify-model.sh"
echo "Tear down:             bash scripts/down.sh"
