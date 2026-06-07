#!/usr/bin/env bash
# Shared helpers: load .env and defaults for local Docker workflows.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

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
: "${MODEL_DTYPE:=bfloat16}"
: "${WEAVE_PROJECT:=openclaw-sandbox}"
