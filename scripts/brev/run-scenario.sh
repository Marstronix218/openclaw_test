#!/usr/bin/env bash
# Run one benchmark scenario with the expected policy state and capture output.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

scenario="${1:-}"
prompts_file="$BREV_ROOT_DIR/benchmarks/openclaw-qwen25-7b/prompts.tsv"

if [[ -z "$scenario" ]]; then
  echo "usage: $0 1|2|3|4a|4b|5|6|7" >&2
  exit 1
fi

line="$(awk -F '\t' -v id="$scenario" '$1 == id { print; exit }' "$prompts_file")"
if [[ -z "$line" ]]; then
  echo "error: unknown scenario '$scenario'" >&2
  exit 1
fi

IFS=$'\t' read -r scenario_id scenario_name prompt <<<"$line"
case "$scenario_id" in
  1|2|4a|4b|5)
    bash "$BREV_ROOT_DIR/scripts/brev/web-policy.sh" allow
    bash "$BREV_ROOT_DIR/scripts/brev/approval-mode.sh" full
    ;;
  3)
    bash "$BREV_ROOT_DIR/scripts/brev/web-policy.sh" deny
    bash "$BREV_ROOT_DIR/scripts/brev/approval-mode.sh" full
    ;;
  6)
    bash "$BREV_ROOT_DIR/scripts/brev/web-policy.sh" allow
    bash "$BREV_ROOT_DIR/scripts/brev/approval-mode.sh" strict
    ;;
  7)
    bash "$BREV_ROOT_DIR/scripts/brev/web-policy.sh" deny
    bash "$BREV_ROOT_DIR/scripts/brev/approval-mode.sh" strict
    ;;
esac

run_dir="$BREV_RUNS_DIR/$(timestamp_utc)-${scenario_id}-${scenario_name}"
mkdir -p "$run_dir"
cp "$BREV_DATA_DIR/run-metadata.txt" "$run_dir/" 2>/dev/null || true
printf 'scenario=%s\nname=%s\nuser=%s\nsession_key=%s\nprompt=%s\n' \
  "$scenario_id" "$scenario_name" "$BENCHMARK_USER" "$BENCHMARK_SESSION_KEY" "$prompt" \
  > "$run_dir/scenario.txt"

openclaw_exec "openclaw config get tools --json" > "$run_dir/tools.json" 2>&1 || true
openclaw_exec "openclaw approvals get --json" > "$run_dir/approvals.json" 2>&1 || true
nvidia-smi --query-gpu=timestamp,name,memory.used,utilization.gpu \
  --format=csv,noheader > "$run_dir/gpu-before.txt"

set +e
docker exec "$BREV_OPENCLAW_CONTAINER" bash -lc \
  "export HOME=/root; unset OPENCLAW_HOME; openclaw agent \
    --agent main \
    --session-key $(printf '%q' "$BENCHMARK_SESSION_KEY") \
    --thinking off \
    --timeout 1200 \
    --json \
    --message $(printf '%q' "$prompt")" \
  > >(tee "$run_dir/response.json") \
  2> >(tee "$run_dir/stderr.log" >&2)
exit_code=$?
set -e

printf '%s\n' "$exit_code" > "$run_dir/exit-code.txt"
nvidia-smi --query-gpu=timestamp,name,memory.used,utilization.gpu \
  --format=csv,noheader > "$run_dir/gpu-after.txt"
docker logs --since 30m "$BREV_VLLM_CONTAINER" > "$run_dir/vllm.log" 2>&1 || true
openclaw_exec "tail -n 1000 /root/.openclaw/weave-proxy.log" > "$run_dir/weave-proxy.log" 2>&1 || true
openclaw_exec "tail -n 1000 /root/.openclaw/gateway.log" > "$run_dir/gateway.log" 2>&1 || true

echo
echo "Artifacts: $run_dir"
exit "$exit_code"
