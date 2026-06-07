#!/usr/bin/env bash
# Run a single chat completion to confirm the local Qwen model (and Weave tracing) work.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

CONTAINER="${LOCAL_CONTAINER:-openclaw-local}"
MSG="${1:-In one short sentence, say hello and name the model you are running on.}"

payload=$(python3 -c 'import json,sys; print(json.dumps({"model":"Qwen/Qwen2.5-1.5B-Instruct","messages":[{"role":"user","content":sys.argv[1]}],"max_tokens":128}))' "$MSG")

docker exec "$CONTAINER" bash -lc "curl -s --max-time 600 http://127.0.0.1:8000/v1/chat/completions \
  -H 'Content-Type: application/json' -d '$payload'" | python3 -c '
import json, sys
data = json.load(sys.stdin)
msg = data["choices"][0]["message"]["content"]
usage = data.get("usage", {})
print(msg)
print(f"\n(tokens: {usage.get(\"prompt_tokens\", \"?\")} prompt + {usage.get(\"completion_tokens\", \"?\")} completion)")
'
