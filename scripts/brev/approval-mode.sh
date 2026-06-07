#!/usr/bin/env bash
# Switch between no-prompt baseline runs and strict approval runs.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

mode="${1:-}"
case "$mode" in
  full)
    openclaw_exec "openclaw config set tools.exec.mode full"
    openclaw_exec "openclaw approvals set --stdin <<'EOF'
{\"version\":1,\"defaults\":{\"security\":\"full\",\"ask\":\"off\",\"askFallback\":\"full\",\"autoAllowSkills\":false},\"agents\":{\"main\":{\"security\":\"full\",\"ask\":\"off\",\"askFallback\":\"full\",\"autoAllowSkills\":false,\"allowlist\":[]}}}
EOF"
    ;;
  strict)
    openclaw_exec "openclaw config set tools.exec.mode ask"
    openclaw_exec "openclaw approvals set --stdin <<'EOF'
{\"version\":1,\"defaults\":{\"security\":\"allowlist\",\"ask\":\"on-miss\",\"askFallback\":\"deny\",\"autoAllowSkills\":false},\"agents\":{\"main\":{\"security\":\"allowlist\",\"ask\":\"on-miss\",\"askFallback\":\"deny\",\"autoAllowSkills\":false,\"allowlist\":[]}}}
EOF"
    ;;
  *)
    echo "usage: $0 full|strict" >&2
    exit 1
    ;;
esac

restart_gateway
echo "Exec approval mode: $mode"
