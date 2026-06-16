#!/usr/bin/env bash
# Save Docker registry credentials to a JSON file.
#
# Usage:
#   # Read password from stdin (recommended — password never in command args):
#   echo 'my-password' | bash .claude/skills/agentbase/scripts/save_registry_credentials.sh \
#     --output-file ./docker-creds.json --username "myuser" --registry "docker.io" --password-stdin
#
#   # Or read password from a file:
#   bash .claude/skills/agentbase/scripts/save_registry_credentials.sh \
#     --output-file ./docker-creds.json --username "myuser" --password-file /tmp/pass.txt --registry "docker.io"
#
# Output file format (JSON):
#   {"username": "...", "password": "...", "registry": "...", "repository": "..."}
#
# The output file can be used with:
#   runtime.sh create --registry-credentials-file <path>
#   docker_login.sh --credentials-file <path>
#
# Also adds the output file to .gitignore and .dockerignore.
# Exit code: 0 = saved, 1 = error

set -euo pipefail

OUTPUT=""
USERNAME=""
PASSWORD=""
PASSWORD_FILE=""
PASSWORD_STDIN=false
REGISTRY=""
REPOSITORY=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-file|-o) OUTPUT="$2"; shift 2 ;;
    --username) USERNAME="$2"; shift 2 ;;
    --password-file) PASSWORD_FILE="$2"; shift 2 ;;
    --password-stdin) PASSWORD_STDIN=true; shift ;;
    --registry) REGISTRY="$2"; shift 2 ;;
    --repository) REPOSITORY="$2"; shift 2 ;;
    *) echo "ERROR: Unknown option: $1" >&2; exit 1 ;;
  esac
done

# Read password from stdin if --password-stdin was given
if [ "$PASSWORD_STDIN" = true ] && [ -z "$PASSWORD" ]; then
  PASSWORD=$(cat | tr -d '\n')
fi

# Read password from file if --password-file was given
if [ -n "$PASSWORD_FILE" ] && [ -z "$PASSWORD" ]; then
  if [ ! -f "$PASSWORD_FILE" ]; then
    echo "ERROR: Password file not found: $PASSWORD_FILE" >&2
    exit 1
  fi
  PASSWORD=$(tr -d '[:space:]' < "$PASSWORD_FILE")
fi

if [ -z "$OUTPUT" ]; then
  echo "ERROR: --output-file <path> is required (e.g., --output-file ./docker-creds.json)" >&2
  exit 1
fi

if [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
  echo "ERROR: --username and (--password, --password-file, or --password-stdin) are required" >&2
  exit 1
fi

if [ -z "$REGISTRY" ]; then
  echo "ERROR: --registry is required (e.g., vcr.vngcloud.vn, docker.io, ghcr.io)" >&2
  exit 1
fi

# Ensure output directory exists
mkdir -p "$(dirname "$OUTPUT")"

# Write credentials to file (not stdout)
jq -n \
  --arg user "$USERNAME" \
  --arg pass "$PASSWORD" \
  --arg reg "$REGISTRY" \
  --arg repo "$REPOSITORY" \
  '{"username": $user, "password": $pass, "registry": $reg, "repository": $repo}' \
  > "$OUTPUT"

# Restrict credentials file permissions (contains secrets)
chmod 600 "$OUTPUT"

# Add output file to .gitignore if not already there
OUTPUT_BASENAME=$(basename "$OUTPUT")
if [ -f ".gitignore" ]; then
  if ! grep -qF "$OUTPUT_BASENAME" .gitignore; then
    echo "$OUTPUT_BASENAME" >> .gitignore
    echo "Added $OUTPUT_BASENAME to .gitignore"
  fi
fi

# Add output file to .dockerignore if not already there
if [ -f ".dockerignore" ]; then
  if ! grep -qF "$OUTPUT_BASENAME" .dockerignore; then
    echo "$OUTPUT_BASENAME" >> .dockerignore
  fi
fi

echo "OK: Registry credentials saved to $OUTPUT (username: $USERNAME, registry: $REGISTRY)"
