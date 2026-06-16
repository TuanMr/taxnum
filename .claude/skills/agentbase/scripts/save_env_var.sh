#!/usr/bin/env bash
# Write or update a key=value pair in .env, reading the value from a file
# or stdin so that the secret never appears in command arguments or stdout.
#
# Usage:
#   # Read value from stdin (recommended — secret never in command args):
#   echo 'my-secret' | bash .claude/skills/agentbase/scripts/save_env_var.sh \
#     --key AIP_API_KEY --value-stdin
#
#   # Or read from a file:
#   bash .claude/skills/agentbase/scripts/save_env_var.sh \
#     --key AIP_API_KEY --value-file /tmp/aip-key.txt
#
#   # Non-secret values can use --value directly:
#   bash .claude/skills/agentbase/scripts/save_env_var.sh \
#     --key LLM_MODEL --value "vngcloud-llama-3.1-70b"
#
#   # Multiple vars at once (non-secret values via --extra):
#   bash .claude/skills/agentbase/scripts/save_env_var.sh \
#     --key AIP_API_KEY --value-stdin \
#     --extra "AIP_BASE_URL=https://maas-llm-aiplatform-hcm.api.vngcloud.vn/v1" \
#     --extra "LLM_MODEL=vngcloud-llama-3.1-70b" < /tmp/aip-key.txt
#
# Exit code: 0 = saved, 1 = error
# stdout: confirmation message (no secret values)

set -euo pipefail

KEY=""
VALUE=""
VALUE_FILE=""
VALUE_STDIN=false
EXTRAS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --key) KEY="$2"; shift 2 ;;
    --value) VALUE="$2"; shift 2 ;;
    --value-file) VALUE_FILE="$2"; shift 2 ;;
    --value-stdin) VALUE_STDIN=true; shift ;;
    --extra) EXTRAS+=("$2"); shift 2 ;;
    *) echo "ERROR: Unknown option: $1" >&2; exit 1 ;;
  esac
done

# Read value from stdin if --value-stdin was given
if [ "$VALUE_STDIN" = true ] && [ -z "$VALUE" ]; then
  VALUE=$(cat | tr -d '\n')
fi

# Read value from file if --value-file was given
if [ -n "$VALUE_FILE" ] && [ -z "$VALUE" ]; then
  if [ ! -f "$VALUE_FILE" ]; then
    echo "ERROR: Value file not found: $VALUE_FILE" >&2
    exit 1
  fi
  VALUE=$(tr -d '[:space:]' < "$VALUE_FILE")
fi

if [ -z "$KEY" ] || [ -z "$VALUE" ]; then
  echo "ERROR: --key and (--value, --value-file, or --value-stdin) are required" >&2
  exit 1
fi

# Write or update the key in .env
if [ -f .env ]; then
  if grep -q "^${KEY}=" .env 2>/dev/null; then
    grep -v "^${KEY}=" .env > .env.tmp && mv .env.tmp .env
    echo "${KEY}=${VALUE}" >> .env
  else
    echo "${KEY}=${VALUE}" >> .env
  fi
else
  echo "${KEY}=${VALUE}" > .env
fi

# Write any extra non-secret key=value pairs
for extra in ${EXTRAS[@]+"${EXTRAS[@]}"}; do
  local_key="${extra%%=*}"
  local_val="${extra#*=}"
  if [ -z "$local_key" ] || [ "$extra" = "$local_key" ]; then
    echo "WARNING: Skipping malformed --extra: $extra" >&2
    continue
  fi
  if grep -q "^${local_key}=" .env 2>/dev/null; then
    grep -v "^${local_key}=" .env > .env.tmp && mv .env.tmp .env
    echo "${local_key}=${local_val}" >> .env
  else
    echo "${local_key}=${local_val}" >> .env
  fi
done

# Ensure .env is in .gitignore (secrets should never be committed)
if [ -f ".gitignore" ]; then
  if ! grep -qxF '.env' .gitignore; then
    echo '.env' >> .gitignore
  fi
else
  echo '.env' > .gitignore
fi

# Ensure .env is in .dockerignore (secrets should not be in container images)
if [ -f ".dockerignore" ]; then
  if ! grep -qxF '.env' .dockerignore; then
    echo '.env' >> .dockerignore
  fi
fi

# Restrict .env file permissions (contains secrets)
chmod 600 .env

echo "OK: ${KEY} saved to .env (length: ${#VALUE} chars)"
