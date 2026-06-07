#!/usr/bin/env bash
# Toggle web_search and web_fetch for the live revoke comparison.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

mode="${1:-}"
case "$mode" in
  allow)
    openclaw_exec "openclaw config set tools.deny '[]' --strict-json"
    ;;
  deny)
    openclaw_exec "openclaw config set tools.deny '[\"web_search\",\"web_fetch\"]' --strict-json"
    ;;
  *)
    echo "usage: $0 allow|deny" >&2
    exit 1
    ;;
esac

restart_gateway
echo "Web tools: $mode"
