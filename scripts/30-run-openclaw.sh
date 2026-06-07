#!/usr/bin/env bash
# Non-interactively onboard the OpenClaw *gateway* (local mode, LAN bind, token
# auth from env) and start it detached inside the sandbox. The model/provider
# auth is intentionally skipped here so you can configure it interactively
# later via `scripts/ssh.sh` -> `openclaw onboard`.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

remote=$(cat <<REMOTE
set -e
export HOME=/root
unset OPENCLAW_HOME
mkdir -p /root/.openclaw/workspace

# One-time gateway onboarding (idempotent-ish: only if no config yet).
if [ ! -f "\$OPENCLAW_HOME/openclaw.json" ]; then
  openclaw onboard \
    --non-interactive \
    --accept-risk \
    --mode local \
    --flow manual \
    --auth-choice skip \
    --gateway-auth token \
    --gateway-token-ref-env OPENCLAW_GATEWAY_TOKEN \
    --gateway-bind lan \
    --gateway-port ${OPENCLAW_PORT} \
    --skip-daemon --skip-channels --skip-skills --skip-search --skip-hooks --skip-ui
fi

# (Re)start the gateway detached so it outlives this exec session.
pkill -f '[o]penclaw gateway --bind' 2>/dev/null || true
sleep 1
setsid bash -c 'openclaw gateway --bind lan --port ${OPENCLAW_PORT} --force >> /root/.openclaw/gateway.log 2>&1' < /dev/null &
sleep 5
echo "--- gateway.log (tail) ---"
tail -n 25 /root/.openclaw/gateway.log 2>/dev/null || echo "(no log yet)"
echo "--- listening sockets ---"
(ss -ltnp 2>/dev/null || netstat -ltnp 2>/dev/null) | grep -E ":${OPENCLAW_PORT}\b" || echo "(port ${OPENCLAW_PORT} not listening yet)"
REMOTE
)

echo "Onboarding + starting OpenClaw gateway inside sandbox '$SANDBOX_NAME'..."
# The gateway is a long-lived child of the exec session, so the exec call never
# returns on its own. Run it in the background locally, give it time to come up,
# then detach — the in-sandbox `setsid` keeps the gateway alive.
"$DAYTONA" exec "$SANDBOX_NAME" -- bash -lc "$remote" &
exec_pid=$!
sleep 25
kill "$exec_pid" 2>/dev/null || true

echo
echo "Gateway status:"
"$DAYTONA" exec "$SANDBOX_NAME" -- bash -lc 'export HOME=/root; tail -n 6 /root/.openclaw/gateway.log 2>/dev/null; (ss -ltn 2>/dev/null || netstat -ltn 2>/dev/null) | grep -E ":'"$OPENCLAW_PORT"'\b" && echo "gateway LISTENING on '"$OPENCLAW_PORT"'" || echo "gateway NOT yet listening"' || true

echo
echo "Public preview URL for the OpenClaw gateway:"
"$DAYTONA" preview-url "$SANDBOX_NAME" --port "$OPENCLAW_PORT"
