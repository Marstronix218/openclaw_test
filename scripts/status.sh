#!/usr/bin/env bash
# Inspect the running OpenClaw stack in the local Docker container.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

CONTAINER="${LOCAL_CONTAINER:-openclaw-local}"
HOST_PORT="${OPENCLAW_PORT:-18789}"

echo "=== container ==="
docker ps -a --filter "name=^${CONTAINER}$" --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}' || true
echo
echo "=== openclaw gateway status ==="
docker exec "$CONTAINER" bash -lc 'export HOME=/root; unset OPENCLAW_HOME; openclaw gateway status || true; echo; echo "--- gateway.log (tail) ---"; tail -n 20 /root/.openclaw/gateway.log 2>/dev/null || true' 2>/dev/null || echo "(container not running)"
echo
echo "=== model server ==="
docker exec "$CONTAINER" bash -lc 'curl -s --max-time 3 http://127.0.0.1:8000/health 2>/dev/null || echo "not responding"; echo; echo "--- server.log (tail) ---"; tail -n 10 /root/model-server/server.log 2>/dev/null || true' 2>/dev/null || true
echo
echo "=== gateway url ==="
echo "http://localhost:${HOST_PORT}  (token: \$OPENCLAW_GATEWAY_TOKEN from .env)"
if [[ -n "${WEAVE_PROJECT:-}" && -n "${WANDB_API_KEY:-}" ]]; then
  echo "=== weave ==="
  docker exec "$CONTAINER" bash -lc 'grep -m1 "View Weave data at" /root/model-server/server.log 2>/dev/null || echo "(check server.log after first traced call)"' 2>/dev/null || true
fi
