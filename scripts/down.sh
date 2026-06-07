#!/usr/bin/env bash
# Tear down the local Docker container (image is kept for fast restarts).
set -euo pipefail
here="$(dirname "${BASH_SOURCE[0]}")"
exec bash "$here/local-down.sh"
