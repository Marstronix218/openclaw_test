#!/usr/bin/env bash
# Stop & remove the local Docker container (image is kept for fast restarts).
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
CONTAINER="${LOCAL_CONTAINER:-openclaw-local}"
docker rm -f "$CONTAINER" 2>/dev/null && echo "Removed container '$CONTAINER'." || echo "No container '$CONTAINER' running."
