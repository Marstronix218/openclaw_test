#!/usr/bin/env bash
# Shared helpers: locate the daytona binary and load .env.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Prefer a system daytona, fall back to the locally-downloaded one.
if command -v daytona >/dev/null 2>&1; then
  DAYTONA="$(command -v daytona)"
elif [[ -x "$ROOT_DIR/.bin/daytona" ]]; then
  DAYTONA="$ROOT_DIR/.bin/daytona"
else
  echo "error: daytona CLI not found (looked on PATH and in .bin/)" >&2
  exit 1
fi
export DAYTONA

if [[ -f "$ROOT_DIR/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$ROOT_DIR/.env"
  set +a
fi

require() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "error: required variable '$name' is not set (check .env)" >&2
    exit 1
  fi
}

# Defaults (overridable via .env)
: "${DAYTONA_TARGET:=us}"
: "${OPENCLAW_CPU:=4}"
: "${OPENCLAW_MEMORY_GB:=8}"
: "${OPENCLAW_DISK_GB:=10}"
: "${SNAPSHOT_NAME:=openclaw-max}"
: "${SANDBOX_NAME:=openclaw}"
: "${OPENCLAW_PORT:=18789}"
