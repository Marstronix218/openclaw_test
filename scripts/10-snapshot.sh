#!/usr/bin/env bash
# Build & push the maxed-out OpenClaw snapshot.
# Underlying sandboxes inherit these resource sizes (4 vCPU / 8 GiB / 10 GiB).
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

echo "Building snapshot '$SNAPSHOT_NAME' (cpu=$OPENCLAW_CPU mem=${OPENCLAW_MEMORY_GB}G disk=${OPENCLAW_DISK_GB}G)"

"$DAYTONA" snapshot create "$SNAPSHOT_NAME" \
  --dockerfile "$ROOT_DIR/snapshot/Dockerfile" \
  --context "$ROOT_DIR/snapshot" \
  --cpu "$OPENCLAW_CPU" \
  --memory "$OPENCLAW_MEMORY_GB" \
  --disk "$OPENCLAW_DISK_GB"

echo "Snapshot ready:"
"$DAYTONA" snapshot list
