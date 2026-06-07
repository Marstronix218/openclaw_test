#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

echo "=== reference hardware ==="
nvidia-smi --query-gpu=index,name,memory.total,memory.used,utilization.gpu \
  --format=csv,noheader 2>/dev/null || true
echo
echo "=== containers ==="
docker ps -a \
  --filter "name=^${BREV_OPENCLAW_CONTAINER}$" \
  --filter "name=^${BREV_VLLM_CONTAINER}$" \
  --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
echo
echo "=== vLLM ==="
curl -fsS --max-time 3 "http://127.0.0.1:${VLLM_HOST_PORT}/v1/models" 2>/dev/null || echo "not responding"
echo
echo
echo "=== Weave tracing proxy ==="
if container_running "$BREV_OPENCLAW_CONTAINER"; then
  openclaw_exec "curl -fsS --max-time 3 http://127.0.0.1:${WEAVE_PROXY_PORT}/health || true"
  echo
  openclaw_exec "grep -m1 'View Weave data at' /root/.openclaw/weave-proxy.log 2>/dev/null || true"
  openclaw_exec "tail -n 20 /root/.openclaw/weave-proxy.log 2>/dev/null || true"
else
  echo "not running"
fi
echo
echo "=== OpenClaw ==="
if container_running "$BREV_OPENCLAW_CONTAINER"; then
  openclaw_exec "openclaw models status || true"
  echo
  openclaw_exec "openclaw config get tools --json || true"
  echo
  openclaw_exec "tail -n 20 /root/.openclaw/gateway.log 2>/dev/null || true"
else
  echo "not running"
fi
