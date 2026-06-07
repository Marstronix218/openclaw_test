#!/usr/bin/env bash
# Run OpenClaw + local Qwen model server (+ optional Weave tracing) in Docker.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require OPENCLAW_GATEWAY_TOKEN

IMAGE="${LOCAL_IMAGE:-openclaw-local}"
CONTAINER="${LOCAL_CONTAINER:-openclaw-local}"
HOST_PORT="${OPENCLAW_PORT:-18789}"

dexec() { docker exec "$CONTAINER" bash -lc "$1"; }

# --- 1. Build the image (torch + model weights baked in) --------------------
echo "==> Building image '$IMAGE' (first build downloads torch + model weights; can take a while)"
docker build -t "$IMAGE" -f "$ROOT_DIR/snapshot/Dockerfile" "$ROOT_DIR/snapshot"

# --- 2. (Re)create the container --------------------------------------------
echo "==> (Re)creating container '$CONTAINER'"
docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
run_env=(
  -e HOME=/root -e TERM=xterm-256color
  -e "OPENCLAW_GATEWAY_TOKEN=$OPENCLAW_GATEWAY_TOKEN"
  -e "WEAVE_PROJECT=$WEAVE_PROJECT"
)
[[ -n "${WANDB_API_KEY:-}" ]] && run_env+=(-e "WANDB_API_KEY=$WANDB_API_KEY")
[[ -n "${ANTHROPIC_API_KEY:-}" ]] && run_env+=(-e "ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY")
[[ -n "${OPENAI_API_KEY:-}" ]] && run_env+=(-e "OPENAI_API_KEY=$OPENAI_API_KEY")

docker run -d --name "$CONTAINER" -p "${HOST_PORT}:18789" "${run_env[@]}" "$IMAGE"

dexec 'mkdir -p /root/model-server'
docker cp "$ROOT_DIR/model-server/server.py" "$CONTAINER:/root/model-server/server.py"

# --- 3. Onboard + start the gateway -----------------------------------------
echo "==> Onboarding + starting the OpenClaw gateway"
dexec "
set -e
export HOME=/root; unset OPENCLAW_HOME
mkdir -p /root/.openclaw/workspace /root/model-server
if [ ! -f /root/.openclaw/openclaw.json ]; then
  openclaw onboard --non-interactive --accept-risk --mode local --flow manual \
    --auth-choice skip \
    --gateway-auth token --gateway-token-ref-env OPENCLAW_GATEWAY_TOKEN \
    --gateway-bind lan --gateway-port 18789 \
    --skip-daemon --skip-channels --skip-skills --skip-search --skip-hooks --skip-ui --skip-health
fi
"

# --- 4. Start the (Weave-traced) model server -------------------------------
echo "==> Starting the Qwen model server (Weave tracing: ${WANDB_API_KEY:+ENABLED}${WANDB_API_KEY:-disabled — set WANDB_API_KEY in .env})"
dexec "
set -e
export HOME=/root; unset OPENCLAW_HOME
python3 -c 'import torch, transformers' || { echo 'image missing torch/transformers' >&2; exit 1; }
pkill -f 'model-server/server.py' 2>/dev/null || true
sleep 1
cd /root/model-server
PYTHONUNBUFFERED=1 MODEL_ID='$MODEL_ID' PORT='$MODEL_PORT' DTYPE='$MODEL_DTYPE' \
  NUM_THREADS='${OPENCLAW_CPU:-4}' MAX_NEW_TOKENS='${MODEL_MAX_NEW_TOKENS:-512}' \
  WANDB_API_KEY='${WANDB_API_KEY:-}' WEAVE_PROJECT='${WEAVE_PROJECT}' \
  setsid bash -c 'python3 /root/model-server/server.py >> /root/model-server/server.log 2>&1' < /dev/null &
"

echo "==> Waiting for the model to load (can take a few minutes on CPU)..."
for i in $(seq 1 60); do
  code=$(dexec "curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:${MODEL_PORT}/health" 2>/dev/null | tr -dc '0-9')
  if [ "$code" = "200" ]; then echo "    model server UP"; break; fi
  sleep 10
done

# --- 5. Wire OpenClaw to the local model + restart gateway ------------------
echo "==> Wiring OpenClaw to the local model"
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
qwen_id=\$(openclaw models list 2>/dev/null | grep -i qwen | awk '{print \$1}' | head -1)
[ -n \"\$qwen_id\" ] && openclaw models set \"\$qwen_id\" || true
openclaw config set agents.defaults.timeoutSeconds 1200 || true
pkill -f 'openclaw gateway' 2>/dev/null || true
sleep 2
setsid bash -c 'openclaw gateway --bind lan --port 18789 --force >> /root/.openclaw/gateway.log 2>&1' < /dev/null &
sleep 5
"

echo
echo "Done. OpenClaw gateway: http://localhost:${HOST_PORT}  (token: \$OPENCLAW_GATEWAY_TOKEN)"
echo "Local model:           $MODEL_ID  (port ${MODEL_PORT} inside container)"
echo "Weave project:         ${WEAVE_PROJECT}  (tracing: ${WANDB_API_KEY:+on}${WANDB_API_KEY:-off})"
echo "Verify a turn:         bash scripts/verify-model.sh"
echo "Tear down:             bash scripts/down.sh"
