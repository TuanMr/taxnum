#!/usr/bin/env bash
# Save IAM credentials (client_id + client_secret) to .greennode.json.
# Follows the same security pattern as save_registry_credentials.sh:
#   - Secret via stdin or file (never in command args)
#   - Auto-adds output file to .gitignore and .dockerignore
#   - No secret values on stdout
#
# Usage:
#   # Read secret from stdin (recommended — secret never in command args):
#   echo 'my-client-secret' | bash .claude/skills/agentbase/scripts/save_iam_credentials.sh \
#     --client-id "3ea63e1b-..." --secret-stdin
#
#   # Or read secret from a file:
#   bash .claude/skills/agentbase/scripts/save_iam_credentials.sh \
#     --client-id "3ea63e1b-..." --secret-file /tmp/secret.txt
#
#   # Import from an existing .greennode.json file the user provides:
#   bash .claude/skills/agentbase/scripts/save_iam_credentials.sh \
#     --from-file /path/to/downloaded/credentials.json
#
# Output file: .greennode.json (in current working directory)
# Format: {"client_id": "...", "client_secret": "..."}
#
# Also adds .greennode.json to .gitignore and .dockerignore.
# Exit code: 0 = saved, 1 = error
# stdout: confirmation message (no secret values)

set -euo pipefail

CLIENT_ID=""
CLIENT_SECRET=""
SECRET_FILE=""
SECRET_STDIN=false
FROM_FILE=""
OUTPUT=".greennode.json"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --client-id) CLIENT_ID="$2"; shift 2 ;;
    --secret-file) SECRET_FILE="$2"; shift 2 ;;
    --secret-stdin) SECRET_STDIN=true; shift ;;
    --from-file) FROM_FILE="$2"; shift 2 ;;
    *) echo "ERROR: Unknown option: $1" >&2; exit 1 ;;
  esac
done

# Mode 1: Import from an existing credentials file
if [ -n "$FROM_FILE" ]; then
  if [ ! -f "$FROM_FILE" ]; then
    echo "ERROR: File not found: $FROM_FILE" >&2
    exit 1
  fi

  # Validate it has required fields
  cid=$(jq -r '.client_id // empty' "$FROM_FILE" 2>/dev/null)
  csec=$(jq -r '.client_secret // empty' "$FROM_FILE" 2>/dev/null)

  if [ -z "$cid" ] || [ -z "$csec" ]; then
    echo "ERROR: $FROM_FILE must contain both 'client_id' and 'client_secret' fields" >&2
    exit 1
  fi

  # Write only the credential fields (strip any extra fields from the source file)
  jq -n \
    --arg cid "$cid" \
    --arg csec "$csec" \
    '{"client_id": $cid, "client_secret": $csec}' \
    > "$OUTPUT"

  CLIENT_ID="$cid"
else
  # Mode 2: Explicit client_id + secret via stdin/file

  # Read secret from stdin if --secret-stdin was given
  if [ "$SECRET_STDIN" = true ] && [ -z "$CLIENT_SECRET" ]; then
    CLIENT_SECRET=$(cat | tr -d '\n')
  fi

  # Read secret from file if --secret-file was given
  if [ -n "$SECRET_FILE" ] && [ -z "$CLIENT_SECRET" ]; then
    if [ ! -f "$SECRET_FILE" ]; then
      echo "ERROR: Secret file not found: $SECRET_FILE" >&2
      exit 1
    fi
    CLIENT_SECRET=$(tr -d '[:space:]' < "$SECRET_FILE")
  fi

  if [ -z "$CLIENT_ID" ] || [ -z "$CLIENT_SECRET" ]; then
    echo "ERROR: Either --from-file <path>, or --client-id and (--secret-stdin, --secret-file) are required" >&2
    exit 1
  fi

  # Write credentials to file (not stdout)
  jq -n \
    --arg cid "$CLIENT_ID" \
    --arg csec "$CLIENT_SECRET" \
    '{"client_id": $cid, "client_secret": $csec}' \
    > "$OUTPUT"
fi

# Add .greennode.json to .gitignore if not already there
if [ -f ".gitignore" ]; then
  if ! grep -qxF '.greennode.json' .gitignore; then
    echo '.greennode.json' >> .gitignore
    echo "Added .greennode.json to .gitignore"
  fi
else
  echo '.greennode.json' > .gitignore
  echo "Created .gitignore with .greennode.json"
fi

# Add .greennode.json to .dockerignore if not already there
if [ -f ".dockerignore" ]; then
  if ! grep -qxF '.greennode.json' .dockerignore; then
    echo '.greennode.json' >> .dockerignore
  fi
fi

echo "OK: IAM credentials saved to $OUTPUT (client_id: ${CLIENT_ID:0:8}...)"
