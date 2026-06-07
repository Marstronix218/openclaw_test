#!/usr/bin/env bash
# End-to-end: build image, start local Docker container, run OpenClaw + model + Weave.
set -euo pipefail
here="$(dirname "${BASH_SOURCE[0]}")"
exec bash "$here/local-up.sh"
