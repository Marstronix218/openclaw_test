#!/usr/bin/env bash
# Run a single chat completion via the HF InferenceClient proxy (Weave-traced when configured).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

CONTAINER="${LOCAL_CONTAINER:-openclaw-local}"
MSG="${1:-In one short sentence, say hello and name the model you are running on.}"
MAX_TOKENS="${VERIFY_MAX_TOKENS:-128}"

payload=$(python3 -c 'import json,sys; print(json.dumps({
    "model": sys.argv[1],
    "messages": [{"role": "user", "content": sys.argv[2]}],
    "max_tokens": int(sys.argv[3]),
}))' "$MODEL_ID" "$MSG" "$MAX_TOKENS")

echo "Sending test prompt via HF InferenceClient proxy ($MODEL_ID on ${HF_MODEL_PROVIDER})..."
response=$(docker exec "$CONTAINER" bash -lc \
  "curl -sS --max-time 600 http://127.0.0.1:${MODEL_PORT}/v1/chat/completions \
    -H 'Content-Type: application/json' -d $(printf '%q' "$payload")") || {
  echo "error: curl failed (is the model server running? bash scripts/status.sh)" >&2
  exit 1
}

printf '%s' "$response" | python3 -c '
import json, sys
raw = sys.stdin.read()
try:
    data = json.loads(raw)
except json.JSONDecodeError:
    print("error: model server returned non-JSON:", raw[:500], file=sys.stderr)
    raise SystemExit(1)
if "error" in data:
    print("error:", data["error"], file=sys.stderr)
    raise SystemExit(1)
msg = data["choices"][0]["message"]["content"]
usage = data.get("usage", {})
print(msg)
pt = usage.get("prompt_tokens", "?")
ct = usage.get("completion_tokens", "?")
print(f"\n(tokens: {pt} prompt + {ct} completion)")
'
