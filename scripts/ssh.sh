#!/usr/bin/env bash
# Drop into an interactive shell in the local Docker container.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
CONTAINER="${LOCAL_CONTAINER:-openclaw-local}"
exec docker exec -it "$CONTAINER" bash
