#!/usr/bin/env bash
# Shared helpers: load .env and defaults for local Docker workflows.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Daytona CLI is optional (legacy scripts only).
if command -v daytona >/dev/null 2>&1; then
  DAYTONA="$(command -v daytona)"
elif [[ -x "$ROOT_DIR/.bin/daytona" ]]; then
  DAYTONA="$ROOT_DIR/.bin/daytona"
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
: "${LOCAL_IMAGE:=openclaw-local}"
: "${LOCAL_CONTAINER:=openclaw-local}"
: "${OPENCLAW_PORT:=18789}"
: "${MODEL_ID:=Qwen/Qwen2.5-1.5B-Instruct}"
: "${MODEL_PORT:=8000}"
: "${HF_MODEL_PROVIDER:=featherless-ai}"
: "${WEAVE_PROJECT:=openclaw-sandbox}"
: "${DAYTONA_TARGET:=us}"
: "${OPENCLAW_CPU:=4}"
: "${OPENCLAW_MEMORY_GB:=8}"
: "${OPENCLAW_DISK_GB:=10}"
: "${SNAPSHOT_NAME:=openclaw-max}"
: "${SANDBOX_NAME:=openclaw}"
