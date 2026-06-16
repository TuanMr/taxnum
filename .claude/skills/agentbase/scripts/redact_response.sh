#!/usr/bin/env bash
# Filter API responses to redact sensitive fields before they enter LLM context.
# Reads full JSON response from stdin, saves raw to file, outputs redacted version.
#
# Usage:
#   curl -s -X POST "..." | bash .claude/skills/agentbase/scripts/redact_response.sh \
#     --fields "secretKey,key,password" \
#     --save-raw .agentbase/last_response.json
#
# Options:
#   --fields FIELD1,FIELD2   Comma-separated list of JSON field names to redact (default: secretKey,key,password,secret,access_token)
#   --save-raw PATH          Save the unredacted response to this file (default: .agentbase/last_response.json)
#   --show-prefix N          Show first N characters of redacted values (default: 0, fully redacted)
#
# Output: JSON with sensitive fields replaced by "********"
# The raw (unredacted) response is saved to the file for scripts that need the actual values.

set -euo pipefail

AGENTBASE_DIR=".agentbase"
FIELDS="secretKey,key,password,secret,access_token"
SAVE_RAW="$AGENTBASE_DIR/last_response.json"
SHOW_PREFIX=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --fields) FIELDS="$2"; shift 2 ;;
    --save-raw) SAVE_RAW="$2"; shift 2 ;;
    --show-prefix) SHOW_PREFIX="$2"; shift 2 ;;
    *) shift ;;
  esac
done

mkdir -p "$AGENTBASE_DIR"

# Read full response from stdin
RESPONSE=$(cat)

# Save raw response to file
echo "$RESPONSE" > "$SAVE_RAW"

# Build jq filter to redact specified fields
# Converts "secretKey,key,password" into a jq walk filter
IFS=',' read -ra FIELD_ARRAY <<< "$FIELDS"

JQ_FILTER="."
for field in "${FIELD_ARRAY[@]}"; do
  field=$(echo "$field" | xargs)  # trim whitespace
  # Escape field name for safe use in jq (handle dots, quotes, special chars)
  escaped_field=$(printf '%s' "$field" | sed 's/\\/\\\\/g; s/"/\\"/g')
  if [ "$SHOW_PREFIX" -gt 0 ]; then
    # Show first N chars + "********"
    JQ_FILTER="$JQ_FILTER | (.. | objects | select(has(\"$escaped_field\")) | .[\"$escaped_field\"]) |= (if type == \"string\" then (.[0:$SHOW_PREFIX] + \"********\") else \"********\" end)"
  else
    JQ_FILTER="$JQ_FILTER | (.. | objects | select(has(\"$escaped_field\")) | .[\"$escaped_field\"]) |= \"********\""
  fi
done

# Output redacted response
# If jq parsing fails (non-JSON response), do NOT echo raw text — it may contain secrets
if echo "$RESPONSE" | jq -e '.' &>/dev/null; then
  echo "$RESPONSE" | jq "$JQ_FILTER" 2>/dev/null || echo "$RESPONSE"
else
  echo "(non-JSON response saved to $SAVE_RAW — not displayed due to potential sensitive content)"
fi
