#!/usr/bin/env bash
# Repair the persisted OpenClaw tool policy without rebuilding either container.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

if ! container_running "$BREV_OPENCLAW_CONTAINER"; then
  echo "error: OpenClaw container '$BREV_OPENCLAW_CONTAINER' is not running" >&2
  exit 1
fi

openclaw_exec "openclaw config set tools.profile minimal"
openclaw_exec "openclaw config set tools.alsoAllow '[\"web_search\",\"web_fetch\",\"read\",\"write\",\"exec\",\"process\"]' --strict-json"
openclaw_exec "openclaw config unset tools.allow"
openclaw_exec "openclaw config set tools.deny '[\"process\",\"apply_patch\"]' --strict-json"

restart_gateway

echo "=== effective tool configuration ==="
openclaw_exec "openclaw config get tools --json"
