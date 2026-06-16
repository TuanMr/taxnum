#!/usr/bin/env bash
# Scan Python source files for required environment variables and check
# which ones are present in .env (or exported in the shell).
#
# SECURITY: This script NEVER outputs env var values. It only reports
# variable names and whether they are set (present/missing).
#
# Usage:
#   bash .claude/skills/agentbase/scripts/check_env.sh [directory]
#
# Output (stdout, one JSON object):
#   {
#     "required": ["LLM_API_KEY", "LLM_BASE_URL", "LLM_MODEL", "MEMORY_ID"],
#     "present":  ["LLM_BASE_URL", "LLM_MODEL"],
#     "missing":  ["LLM_API_KEY", "MEMORY_ID"]
#   }
#
# Exit code: 0 = all present, 1 = some missing, 2 = no env vars found in code

set -euo pipefail

SCAN_DIR="${1:-.}"

# --- Step 1: Scan Python files for env var references ---
# Patterns matched:
#   os.environ.get("VAR"...)   os.environ.get('VAR'...)
#   os.getenv("VAR"...)        os.getenv('VAR'...)
#   os.environ["VAR"]          os.environ['VAR']

REQUIRED_VARS=$(
  grep -rEoh \
    'os\.environ\.get\(\s*["\x27]([A-Za-z_][A-Za-z0-9_]*)["\x27]|os\.getenv\(\s*["\x27]([A-Za-z_][A-Za-z0-9_]*)["\x27]|os\.environ\[\s*["\x27]([A-Za-z_][A-Za-z0-9_]*)["\x27]\s*\]' \
    --include='*.py' "$SCAN_DIR" 2>/dev/null \
  | grep -oE '[A-Z_][A-Z0-9_]{2,}' \
  | sort -u
)

if [ -z "$REQUIRED_VARS" ]; then
  echo '{"required":[],"present":[],"missing":[]}'
  exit 2
fi

# --- Step 2: Check each var against .env file and environment ---
PRESENT=()
MISSING=()

for var in $REQUIRED_VARS; do
  found=false

  # Check shell environment
  if [ -n "${!var:-}" ] 2>/dev/null; then
    found=true
  fi

  # Check .env file (key existence only, never read value)
  if [ "$found" = false ] && [ -f .env ]; then
    if grep -qE "^${var}=.+" .env 2>/dev/null; then
      found=true
    fi
  fi

  if [ "$found" = true ]; then
    PRESENT+=("$var")
  else
    MISSING+=("$var")
  fi
done

# --- Step 3: Output JSON ---
to_json_array() {
  local arr=("$@")
  if [ ${#arr[@]} -eq 0 ]; then
    echo "[]"
    return
  fi
  printf '['; local first=true
  for item in "${arr[@]}"; do
    [ "$first" = true ] && first=false || printf ','
    printf '"%s"' "$item"
  done
  printf ']'
}

REQ_ARR=($REQUIRED_VARS)

printf '{"required":%s,"present":%s,"missing":%s}\n' \
  "$(to_json_array "${REQ_ARR[@]}")" \
  "$(to_json_array "${PRESENT[@]+"${PRESENT[@]}"}")" \
  "$(to_json_array "${MISSING[@]+"${MISSING[@]}"}")"

if [ ${#MISSING[@]} -gt 0 ]; then
  exit 1
else
  exit 0
fi
