#!/usr/bin/env bash
# Export redacted config, logs, sessions, and hardware metadata for comparison.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

output="${1:-$BREV_ROOT_DIR/artifacts/openclaw-brev-qwen25-7b-$(timestamp_utc).tar.gz}"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
mkdir -p "$(dirname "$output")" "$tmp_dir/openclaw"

cp "$BREV_DATA_DIR/run-metadata.txt" "$tmp_dir/" 2>/dev/null || true
nvidia-smi -q > "$tmp_dir/nvidia-smi.txt" 2>&1 || true
docker logs "$BREV_VLLM_CONTAINER" > "$tmp_dir/vllm.log" 2>&1 || true
openclaw_exec "tail -n 5000 /root/.openclaw/weave-proxy.log" > "$tmp_dir/openclaw/weave-proxy.log" 2>&1 || true
openclaw_exec "tail -n 5000 /root/.openclaw/gateway.log" > "$tmp_dir/openclaw/gateway.log" 2>&1 || true
openclaw_exec "openclaw doctor --deep" > "$tmp_dir/openclaw/doctor.txt" 2>&1 || true
openclaw_exec "openclaw models status" > "$tmp_dir/openclaw/models.txt" 2>&1 || true

if [[ -f "$BREV_OPENCLAW_STATE/openclaw.json" ]]; then
  jq 'walk(
    if type == "object" then
      with_entries(
        if (.key | test("token|apiKey|password|secret"; "i"))
        then .value = "<redacted>"
        else .
        end
      )
    else .
    end
  )' "$BREV_OPENCLAW_STATE/openclaw.json" > "$tmp_dir/openclaw/openclaw.redacted.json"
fi

if [[ -d "$BREV_OPENCLAW_STATE/agents/main/sessions" ]]; then
  cp -R "$BREV_OPENCLAW_STATE/agents/main/sessions" "$tmp_dir/openclaw/sessions"
fi

tar -C "$tmp_dir" -czf "$output" .
echo "Wrote $output"
