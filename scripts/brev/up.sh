#!/usr/bin/env bash
# Start local Qwen2.5-7B on the Brev A100 and wire an isolated OpenClaw to it.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require OPENCLAW_GATEWAY_TOKEN
need docker
need curl
need nvidia-smi

gpu_count="$(nvidia-smi --query-gpu=name --format=csv,noheader | wc -l | tr -d ' ')"
gpu_name="$(nvidia-smi --query-gpu=name --format=csv,noheader -i "$GPU_DEVICE" | head -1)"
if [[ "$gpu_count" -ne 1 ]]; then
  echo "warning: expected one GPU for the reference comparison; found $gpu_count" >&2
fi
if [[ "$gpu_name" != *"A100"* ]]; then
  echo "warning: expected an NVIDIA A100 80GB; found '$gpu_name'" >&2
fi

mkdir -p "$BREV_HF_CACHE" "$BREV_OPENCLAW_STATE/workspace"

echo "==> Building isolated OpenClaw image ($BREV_OPENCLAW_VERSION)"
docker build \
  --build-arg "OPENCLAW_VERSION=$BREV_OPENCLAW_VERSION" \
  -t "$BREV_OPENCLAW_IMAGE" \
  -f "$BREV_ROOT_DIR/brev/Dockerfile" \
  "$BREV_ROOT_DIR/brev"

docker network inspect "$BREV_DOCKER_NETWORK" >/dev/null 2>&1 || \
  docker network create "$BREV_DOCKER_NETWORK" >/dev/null

echo "==> Starting vLLM with $MODEL_ID on $gpu_name"
docker rm -f "$BREV_VLLM_CONTAINER" >/dev/null 2>&1 || true
vllm_env=()
if [[ -n "${HF_TOKEN:-}" ]]; then
  vllm_env=(-e "HF_TOKEN=$HF_TOKEN" -e "HUGGING_FACE_HUB_TOKEN=$HF_TOKEN")
fi
docker run -d \
  --name "$BREV_VLLM_CONTAINER" \
  --network "$BREV_DOCKER_NETWORK" \
  --gpus "device=$GPU_DEVICE" \
  --ipc host \
  -p "127.0.0.1:${VLLM_HOST_PORT}:8000" \
  -v "$BREV_HF_CACHE:/root/.cache/huggingface" \
  "${vllm_env[@]}" \
  "$BREV_VLLM_IMAGE" \
  --model "$MODEL_ID" \
  --served-model-name "$MODEL_ID" \
  --dtype "$VLLM_DTYPE" \
  --gpu-memory-utilization "$VLLM_GPU_MEMORY_UTILIZATION" \
  --max-model-len "$VLLM_MAX_MODEL_LEN" \
  --max-num-seqs "$VLLM_MAX_NUM_SEQS" >/dev/null

echo "==> Waiting for model download and vLLM readiness"
ready=0
for _ in $(seq 1 180); do
  if curl -fsS --max-time 3 "http://127.0.0.1:${VLLM_HOST_PORT}/health" >/dev/null 2>&1; then
    ready=1
    break
  fi
  if ! container_running "$BREV_VLLM_CONTAINER"; then
    echo "error: vLLM exited during startup" >&2
    docker logs --tail 100 "$BREV_VLLM_CONTAINER" >&2 || true
    exit 1
  fi
  sleep 5
done
if [[ "$ready" -ne 1 ]]; then
  echo "error: timed out waiting for vLLM" >&2
  docker logs --tail 100 "$BREV_VLLM_CONTAINER" >&2 || true
  exit 1
fi

echo "==> Starting isolated OpenClaw"
docker rm -f "$BREV_OPENCLAW_CONTAINER" >/dev/null 2>&1 || true
openclaw_env=(
  -e HOME=/root
  -e TERM=xterm-256color
  -e "OPENCLAW_GATEWAY_TOKEN=$OPENCLAW_GATEWAY_TOKEN"
  -e "MODEL_ID=$MODEL_ID"
  -e "VLLM_BASE_URL=http://${BREV_VLLM_CONTAINER}:8000/v1"
  -e "WEAVE_PROXY_PORT=$WEAVE_PROXY_PORT"
  -e "WEAVE_PROJECT=$WEAVE_PROJECT"
)
[[ -n "${WANDB_API_KEY:-}" ]] && openclaw_env+=(-e "WANDB_API_KEY=$WANDB_API_KEY")

docker run -d \
  --name "$BREV_OPENCLAW_CONTAINER" \
  --network "$BREV_DOCKER_NETWORK" \
  -p "127.0.0.1:${OPENCLAW_PORT}:18789" \
  -v "$BREV_OPENCLAW_STATE:/root/.openclaw" \
  "${openclaw_env[@]}" \
  "$BREV_OPENCLAW_IMAGE" >/dev/null

openclaw_exec "mkdir -p /root/.openclaw/workspace"

echo "==> Starting Weave tracing proxy"
docker exec -d "$BREV_OPENCLAW_CONTAINER" bash -lc \
  "exec python3 /opt/openclaw/weave_proxy.py >> /root/.openclaw/weave-proxy.log 2>&1"
proxy_ready=0
for _ in $(seq 1 30); do
  if docker exec "$BREV_OPENCLAW_CONTAINER" curl -fsS --max-time 3 \
    "http://127.0.0.1:${WEAVE_PROXY_PORT}/health" >/dev/null 2>&1; then
    proxy_ready=1
    break
  fi
  sleep 2
done
if [[ "$proxy_ready" -ne 1 ]]; then
  echo "error: Weave tracing proxy failed to start" >&2
  openclaw_exec "cat /root/.openclaw/weave-proxy.log" >&2 || true
  exit 1
fi

if [[ ! -f "$BREV_OPENCLAW_STATE/openclaw.json" ]]; then
  openclaw_exec "openclaw onboard \
    --non-interactive --accept-risk \
    --mode local --flow manual --auth-choice skip \
    --gateway-auth token --gateway-token-ref-env OPENCLAW_GATEWAY_TOKEN \
    --gateway-bind lan --gateway-port 18789 \
    --skip-daemon --skip-channels --skip-skills --skip-search --skip-hooks --skip-ui --skip-health"
fi

provider_json="$(printf '{"baseUrl":"http://127.0.0.1:%s/v1","apiKey":"local","api":"openai-completions","timeoutSeconds":1200,"models":[{"id":"%s","name":"Qwen2.5 7B Instruct (Brev A100)","reasoning":false,"input":["text"],"cost":{"input":0,"output":0,"cacheRead":0,"cacheWrite":0},"contextWindow":%s,"maxTokens":2048}]}' \
  "$WEAVE_PROXY_PORT" "$MODEL_ID" "$VLLM_MAX_MODEL_LEN")"

echo "==> Configuring local-only model"
openclaw_exec "openclaw config set models.mode replace"
openclaw_exec "openclaw config set models.pricing.enabled false --strict-json"
openclaw_exec "openclaw config set models.providers.brevvllm '$provider_json' --strict-json"
openclaw_exec "openclaw config set agents.defaults.model.primary 'brevvllm/$MODEL_ID'"
openclaw_exec "openclaw config set agents.defaults.timeoutSeconds 1200 --strict-json"
openclaw_exec "openclaw config unset tools || true"
openclaw_exec "openclaw config unset skills.allowBundled || true"
openclaw_exec "rm -f /root/.openclaw/exec-approvals.json"
openclaw_exec "openclaw config set gateway.controlUi.allowedOrigins '[\"http://localhost:${OPENCLAW_PORT}\",\"http://127.0.0.1:${OPENCLAW_PORT}\"]' --strict-json"

restart_gateway

actual_openclaw_version="$(openclaw_exec "openclaw --version" | tail -1)"
if [[ -n "${WANDB_API_KEY:-}" ]]; then
  weave_status=enabled
else
  weave_status=disabled
fi
cat > "$BREV_DATA_DIR/run-metadata.txt" <<EOF
created_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
provider=Hyperstack via Brev
brev_machine_type=hyperstack_A100_80G
gpu=$gpu_name
gpu_count=$gpu_count
model=$MODEL_ID
model_runtime=vLLM
weave_project=$WEAVE_PROJECT
weave_tracing=$weave_status
vllm_image=$BREV_VLLM_IMAGE
vllm_dtype=$VLLM_DTYPE
vllm_gpu_memory_utilization=$VLLM_GPU_MEMORY_UTILIZATION
vllm_max_model_len=$VLLM_MAX_MODEL_LEN
openclaw_version=$actual_openclaw_version
EOF

echo
echo "OpenClaw: http://localhost:${OPENCLAW_PORT}"
echo "vLLM API: http://127.0.0.1:${VLLM_HOST_PORT}/v1"
echo "Tracing:  Weave $weave_status (project: $WEAVE_PROJECT)"
echo "Model:    $MODEL_ID (local on $gpu_name)"
echo "Verify:   bash scripts/brev/verify.sh"
