#!/usr/bin/env bash
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

prompt="${1:-In one short sentence, identify the model serving this response.}"

echo "=== direct vLLM completion ==="
payload="$(printf '%s' "$prompt" | docker exec -i "$BREV_OPENCLAW_CONTAINER" jq -Rs \
  --arg model "$MODEL_ID" \
  '{model:$model,messages:[{role:"user",content:.}],temperature:0,max_tokens:64}')"
docker exec "$BREV_OPENCLAW_CONTAINER" curl -fsS --max-time 600 \
  "http://${BREV_VLLM_CONTAINER}:8000/v1/chat/completions" \
  -H 'Content-Type: application/json' \
  -d "$payload" | docker exec -i "$BREV_OPENCLAW_CONTAINER" jq -r \
  '.choices[0].message.content, ("tokens=" + (.usage.total_tokens | tostring))'

echo
echo "=== OpenClaw agent completion ==="
docker exec "$BREV_OPENCLAW_CONTAINER" bash -lc \
  "export HOME=/root; unset OPENCLAW_HOME; openclaw agent \
    --agent main \
    --session-key brev-verification \
    --thinking off \
    --timeout 600 \
    --message $(printf '%q' "$prompt")"
