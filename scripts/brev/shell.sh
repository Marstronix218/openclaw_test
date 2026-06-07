#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
exec docker exec -it "$BREV_OPENCLAW_CONTAINER" bash
