#!/usr/bin/env bash
# Docker login — password never appears on stdout.
# Accepts explicit arguments or reads from a credentials file.
#
# Usage:
#   bash .claude/skills/agentbase/scripts/docker_login.sh --credentials-file ./docker-creds.json
#   bash .claude/skills/agentbase/scripts/docker_login.sh --registry REGISTRY --username USER --password-stdin
#   bash .claude/skills/agentbase/scripts/docker_login.sh --registry REGISTRY --username USER --password-file /tmp/pass.txt
#
# When --save is passed, also saves credentials to the specified output file
# (for later use by runtime.sh --registry-credentials-file).
#
# Exit code: 0 = login succeeded, 1 = failed

set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"

REGISTRY=""
USERNAME=""
PASSWORD=""
PASSWORD_FILE=""
PASSWORD_STDIN=false
CREDENTIALS_FILE=""
SAVE_CREDS=false
SAVE_OUTPUT=""

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --registry) REGISTRY="$2"; shift 2 ;;
    --username) USERNAME="$2"; shift 2 ;;
    --password-file) PASSWORD_FILE="$2"; shift 2 ;;
    --password-stdin) PASSWORD_STDIN=true; shift ;;
    --credentials-file) CREDENTIALS_FILE="$2"; shift 2 ;;
    --save) SAVE_CREDS=true; shift ;;
    --save-to-file) SAVE_CREDS=true; SAVE_OUTPUT="$2"; shift 2 ;;
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

# Read from credentials file if provided
if [ -n "$CREDENTIALS_FILE" ]; then
  if [ ! -f "$CREDENTIALS_FILE" ]; then
    echo "ERROR: Credentials file not found: $CREDENTIALS_FILE" >&2
    exit 1
  fi
  [ -z "$USERNAME" ] && USERNAME=$(jq -r '.username // empty' "$CREDENTIALS_FILE" 2>/dev/null)
  [ -z "$PASSWORD" ] && PASSWORD=$(jq -r '.password // empty' "$CREDENTIALS_FILE" 2>/dev/null)
  [ -z "$REGISTRY" ] && REGISTRY=$(jq -r '.registry // empty' "$CREDENTIALS_FILE" 2>/dev/null)
fi

if [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
  echo "ERROR: Username and password are required. Provide via --credentials-file, --password-stdin, or explicit arguments." >&2
  exit 1
fi

if [ -z "$REGISTRY" ]; then
  echo "ERROR: --registry is required (e.g., vcr.vngcloud.vn, docker.io, ghcr.io)" >&2
  exit 1
fi

# Login using --password-stdin (password never on command line or stdout)
echo "$PASSWORD" | docker login "$REGISTRY" -u "$USERNAME" --password-stdin

# Save credentials for later use by runtime.sh --registry-credentials
if [ "$SAVE_CREDS" = true ]; then
  if [ -z "$SAVE_OUTPUT" ]; then
    echo "ERROR: --save requires --save-to-file <path> to specify where to save credentials" >&2
    exit 1
  fi
  echo "$PASSWORD" | bash "$SCRIPTS_DIR/save_registry_credentials.sh" \
    --output-file "$SAVE_OUTPUT" \
    --username "$USERNAME" \
    --password-stdin \
    --registry "$REGISTRY"
fi
