#!/usr/bin/env bash
# Ship the OpenAI-compatible Qwen server into the sandbox, install CPU-only
# torch + deps, download the model, and start it detached on port 8000.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

: "${MODEL_ID:=Qwen/Qwen2.5-1.5B-Instruct}"
: "${MODEL_PORT:=8000}"
: "${MODEL_DTYPE:=bfloat16}"
: "${WEAVE_PROJECT:=openclaw-sandbox}"

srv_b64=$(base64 < "$ROOT_DIR/model-server/server.py" | tr -d '\n')

echo "Deploying model server into sandbox '$SANDBOX_NAME' (torch + weights are pre-baked in the snapshot)..."

remote=$(cat <<REMOTE
set -e
export HOME=/root
unset OPENCLAW_HOME
mkdir -p /root/model-server
echo '$srv_b64' | base64 -d > /root/model-server/server.py

# torch + model are baked into the snapshot; fail fast if that ever changes.
if ! python3 -c "import torch, transformers" 2>/dev/null; then
  echo "ERROR: torch/transformers not present in image. Rebuild the snapshot (scripts/10-snapshot.sh)." >&2
  exit 1
fi

# Weave tracing (optional): only needed when WANDB_API_KEY is set. It is baked
# into newer snapshots; install on the fly for older ones (PyPI is reachable).
if [ -n "${WANDB_API_KEY:-}" ] && ! python3 -c "import weave" 2>/dev/null; then
  echo "[weave] not in image; installing from PyPI ..."
  python3 -m pip install --quiet --break-system-packages "weave>=0.51.0" || \
    echo "[weave] WARN: install failed; server will run without tracing." >&2
fi

# (Re)start the server detached.
# Anchor to the python process only; a bare path match kills this shell's cmdline.
pkill -f '^python3 /root/model-server/server.py' 2>/dev/null || true
sleep 1
cd /root/model-server
# nproc reports host CPUs inside a Daytona sandbox; pin threads to the real
# vCPU allocation to avoid oversubscription.
PYTHONUNBUFFERED=1 MODEL_ID='$MODEL_ID' PORT='$MODEL_PORT' DTYPE='$MODEL_DTYPE' \
  NUM_THREADS='${OPENCLAW_CPU:-4}' MAX_NEW_TOKENS='${MODEL_MAX_NEW_TOKENS:-512}' \
  WANDB_API_KEY='${WANDB_API_KEY:-}' WEAVE_PROJECT='${WEAVE_PROJECT}' \
  setsid bash -c 'python3 /root/model-server/server.py >> /root/model-server/server.log 2>&1' < /dev/null &
echo "[server] starting; waiting for model load + /health ..."
REMOTE
)

"$DAYTONA" exec "$SANDBOX_NAME" -- bash -lc "$remote"

echo "Polling /health (model load can take a few minutes on CPU)..."
set +e
for i in $(seq 1 60); do
  code=$("$DAYTONA" exec "$SANDBOX_NAME" -- bash -lc "curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:${MODEL_PORT}/health 2>/dev/null" 2>/dev/null | tr -dc '0-9')
  if [ "$code" = "200" ]; then
    echo "Model server is UP on port ${MODEL_PORT}."
    "$DAYTONA" exec "$SANDBOX_NAME" -- bash -lc "curl -s http://127.0.0.1:${MODEL_PORT}/v1/models" 2>/dev/null | grep -v '^declare' || true
    exit 0
  fi
  sleep 10
done

echo "Timed out waiting for /health. Recent server.log:"
"$DAYTONA" exec "$SANDBOX_NAME" -- bash -lc 'tail -n 40 /root/model-server/server.log 2>/dev/null' 2>/dev/null | grep -v '^declare'
exit 1
