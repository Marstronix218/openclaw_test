#!/usr/bin/env bash
# Authenticate the Daytona CLI with your API key.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require DAYTONA_API_KEY

"$DAYTONA" login --api-key "$DAYTONA_API_KEY"
echo "Logged in to Daytona."
