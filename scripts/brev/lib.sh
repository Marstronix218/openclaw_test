#!/usr/bin/env bash
set -euo pipefail

BREV_ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BREV_ENV_FILE="${BREV_ENV_FILE:-$BREV_ROOT_DIR/.env.brev}"

if [[ -f "$BREV_ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$BREV_ENV_FILE"
  set +a
fi

: "${MODEL_ID:=Qwen/Qwen2.5-7B-Instruct}"
: "${BREV_OPENCLAW_CONTAINER:=openclaw-brev-qwen25-7b}"
: "${BREV_VLLM_CONTAINER:=vllm-brev-qwen25-7b}"
: "${BREV_DOCKER_NETWORK:=openclaw-brev-qwen25-7b}"
: "${BREV_OPENCLAW_IMAGE:=openclaw-brev:latest}"
: "${BREV_VLLM_IMAGE:=vllm/vllm-openai:v0.11.0}"
: "${BREV_DATA_DIR:=$BREV_ROOT_DIR/.brev-data}"
: "${OPENCLAW_PORT:=18789}"
: "${VLLM_HOST_PORT:=8000}"
: "${WEAVE_PROXY_PORT:=8001}"
: "${WEAVE_PROJECT:=openclaw-qwen25-7b}"
: "${GPU_DEVICE:=0}"
: "${VLLM_DTYPE:=bfloat16}"
: "${VLLM_GPU_MEMORY_UTILIZATION:=0.85}"
: "${VLLM_MAX_MODEL_LEN:=8192}"
: "${VLLM_MAX_NUM_SEQS:=16}"
: "${BREV_OPENCLAW_VERSION:=2026.6.1}"
: "${BENCHMARK_USER:=alice}"
: "${BENCHMARK_SESSION_KEY:=openclaw-qwen25-7b-alice}"

BREV_DATA_DIR="$(cd "$(dirname "$BREV_DATA_DIR")" 2>/dev/null && pwd)/$(basename "$BREV_DATA_DIR")"
BREV_HF_CACHE="$BREV_DATA_DIR/huggingface"
BREV_OPENCLAW_STATE="$BREV_DATA_DIR/openclaw"
BREV_RUNS_DIR="$BREV_DATA_DIR/runs"

require() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "error: required variable '$name' is not set (check $BREV_ENV_FILE)" >&2
    exit 1
  fi
}

need() {
  local command_name="$1"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "error: '$command_name' is required" >&2
    exit 1
  fi
}

container_running() {
  docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null | grep -qx true
}

openclaw_exec() {
  docker exec "$BREV_OPENCLAW_CONTAINER" bash -lc \
    "export HOME=/root; unset OPENCLAW_HOME; $*"
}

restart_gateway() {
  docker exec "$BREV_OPENCLAW_CONTAINER" bash -lc \
    "pkill -f '[o]penclaw gateway' 2>/dev/null || true"
  sleep 2
  openclaw_exec ": > /root/.openclaw/gateway.log"
  docker exec -d "$BREV_OPENCLAW_CONTAINER" bash -lc \
    "export HOME=/root; unset OPENCLAW_HOME; exec openclaw gateway --bind lan --port 18789 --force >> /root/.openclaw/gateway.log 2>&1"

  local ready=0
  for _ in $(seq 1 30); do
    if docker exec "$BREV_OPENCLAW_CONTAINER" \
      curl -fsS --max-time 2 http://127.0.0.1:18789/readyz >/dev/null 2>&1; then
      ready=1
      break
    fi
    sleep 1
  done

  if [[ "$ready" -ne 1 ]]; then
    echo "error: OpenClaw gateway did not become ready" >&2
    openclaw_exec "tail -n 100 /root/.openclaw/gateway.log" >&2 || true
    return 1
  fi
}

timestamp_utc() {
  date -u +%Y%m%dT%H%M%SZ
}
