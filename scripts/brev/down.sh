#!/usr/bin/env bash
# Remove the Brev containers; cached weights and OpenClaw state are retained.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

docker rm -f "$BREV_OPENCLAW_CONTAINER" "$BREV_VLLM_CONTAINER" >/dev/null 2>&1 || true
docker network rm "$BREV_DOCKER_NETWORK" >/dev/null 2>&1 || true
echo "Stopped Brev stack. Persistent data remains in $BREV_DATA_DIR"
