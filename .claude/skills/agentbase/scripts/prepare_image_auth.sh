#!/usr/bin/env bash
# Prepare imageAuth JSON for runtime API calls with private registries.
# Reads credentials from a credentials file or env vars and writes
# the imageAuth payload to .agentbase/imageauth.json — credentials never
# appear on stdout.
#
# Usage:
#   bash .claude/skills/agentbase/scripts/prepare_image_auth.sh --credentials-file <path>
#
# After running, merge into your runtime payload:
#   jq -s '.[0] * .[1]' payload.json .agentbase/imageauth.json | curl -d @- ...
#
# Exit code: 0 = imageauth.json written, 1 = credentials missing

set -euo pipefail

AGENTBASE_DIR=".agentbase"
OUTPUT_FILE="$AGENTBASE_DIR/imageauth.json"

mkdir -p "$AGENTBASE_DIR"

USERNAME=""
PASSWORD=""
CREDENTIALS_FILE=""

# Parse arguments (allow explicit override)
while [[ $# -gt 0 ]]; do
  case "$1" in
    --credentials-file) CREDENTIALS_FILE="$2"; shift 2 ;;
    *) echo "ERROR: Unknown option: $1" >&2; exit 1 ;;
  esac
done

# Read from credentials file if provided
if [ -n "$CREDENTIALS_FILE" ] && ([ -z "$USERNAME" ] || [ -z "$PASSWORD" ]); then
  if [ ! -f "$CREDENTIALS_FILE" ]; then
    echo "ERROR: Credentials file not found: $CREDENTIALS_FILE" >&2
    exit 1
  fi
  USERNAME=$(jq -r '.username // empty' "$CREDENTIALS_FILE" 2>/dev/null)
  PASSWORD=$(jq -r '.password // empty' "$CREDENTIALS_FILE" 2>/dev/null)
fi

# Fallback to environment variables
if [ -z "$USERNAME" ]; then USERNAME="${REGISTRY_USERNAME:-}"; fi
if [ -z "$PASSWORD" ]; then PASSWORD="${REGISTRY_PASSWORD:-}"; fi

if [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
  echo "MISSING: Registry credentials not found. Provide via --credentials-file <path> or REGISTRY_USERNAME/REGISTRY_PASSWORD env vars." >&2
  exit 1
fi

# Write imageAuth JSON to file (credentials stay out of stdout)
jq -n \
  --arg user "$USERNAME" \
  --arg pass "$PASSWORD" \
  '{"imageAuth": {"enabled": true, "username": $user, "password": $pass}}' \
  > "$OUTPUT_FILE"

echo "OK: imageAuth written to $OUTPUT_FILE (username: $USERNAME)"
