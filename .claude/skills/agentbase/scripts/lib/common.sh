#!/usr/bin/env bash
# GreenNode AgentBase — Shared functions for all resource scripts.
# Source this file after config.sh.
# Usage: source "$(dirname "$0")/lib/common.sh"

set -euo pipefail

# --- Global flags (set by parse_flags or per-call env) ---
VERBOSE="${VERBOSE:-false}"
DRY_RUN="${DRY_RUN:-false}"
OUTPUT_FORMAT="${OUTPUT_FORMAT:-json}"
REDACT_FIELDS="${REDACT_FIELDS:-}"
SAVE_AS="${SAVE_AS:-}"

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENTBASE_DIR=".agentbase"

# --- Dependency check ---
check_deps() {
  for cmd in curl jq; do
    if ! command -v "$cmd" &>/dev/null; then
      echo "ERROR: '$cmd' is required but not installed." >&2
      exit 1
    fi
  done
}

# --- Token management ---
init_token() {
  local force_flag="${1:-}"
  if [ -n "${TOKEN:-}" ] && [ "$force_flag" != "--force" ]; then
    return 0
  fi
  TOKEN=$(bash "$SCRIPTS_DIR/get_token.sh" $force_flag)
  if [ -z "$TOKEN" ]; then
    echo "ERROR: Failed to obtain IAM token. Run: bash .claude/skills/agentbase/scripts/check_credentials.sh iam" >&2
    exit 1
  fi
  export TOKEN
}

# --- Parse common flags from argument list ---
# Usage: ARGS=($(parse_flags "$@"))
# Sets VERBOSE, DRY_RUN, OUTPUT_FORMAT, REDACT_FIELDS as side effects.
# Returns remaining args via stdout (one per line).
parse_flags() {
  local remaining=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --verbose|-v) VERBOSE=true; shift ;;
      --dry-run) DRY_RUN=true; shift ;;
      --output) OUTPUT_FORMAT="$2"; shift 2 ;;
      --redact) REDACT_FIELDS="$2"; shift 2 ;;
      *) remaining+=("$1"); shift ;;
    esac
  done
  if [ ${#remaining[@]} -gt 0 ]; then
    printf '%s\n' "${remaining[@]}"
  fi
}

# --- Core API call ---
# api_call METHOD URL [BODY]
# Handles auth, verbose, dry-run, error handling, redaction.
# Outputs response body (JSON) on success; returns 1 on failure.
#
# Environment variables (set before call):
#   REDACT_FIELDS  — comma-separated fields to redact in stdout output
#   SAVE_AS        — save raw response to this file instead of last_response.json
#                    (use when chaining calls and you need to preserve earlier responses)
#
# Raw response is always saved to:
#   $SAVE_AS if set, otherwise .agentbase/last_response.json
api_call() {
  local method="$1"
  local url="$2"
  local body="${3:-}"

  init_token

  # Verbose logging
  if [ "$VERBOSE" = true ]; then
    echo ">>> $method $url" >&2
    [ -n "$body" ] && echo ">>> Body: (redacted — use --dry-run to see curl command)" >&2
  fi

  # Dry-run mode
  if [ "$DRY_RUN" = true ]; then
    echo "curl -s -X $method \"$url\" \\"
    echo "  -H \"Authorization: Bearer \$TOKEN\" \\"
    if [ -n "$body" ]; then
      echo "  -H \"Content-Type: application/json\" \\"
      echo "  -d '$body'"
    else
      echo "  -H \"Content-Type: application/json\""
    fi
    return 0
  fi

  # Build curl args
  local curl_args=(-s -w '\n%{http_code}' -X "$method" "$url"
    -H "Authorization: Bearer $TOKEN"
    -H "Content-Type: application/json"
  )
  if [ -n "$body" ]; then
    curl_args+=(-d "$body")
  fi

  # Execute
  local raw_response
  raw_response=$(curl "${curl_args[@]}")

  local http_code
  http_code=$(echo "$raw_response" | tail -1)
  local response_body
  response_body=$(echo "$raw_response" | sed '$d')

  # Verbose response
  if [ "$VERBOSE" = true ]; then
    echo "<<< HTTP $http_code" >&2
  fi

  # Handle 401 — retry once with fresh token
  if [ "$http_code" = "401" ]; then
    if [ "$VERBOSE" = true ]; then
      echo ">>> Token expired, refreshing..." >&2
    fi
    init_token --force
    curl_args=(-s -w '\n%{http_code}' -X "$method" "$url"
      -H "Authorization: Bearer $TOKEN"
      -H "Content-Type: application/json"
    )
    if [ -n "$body" ]; then
      curl_args+=(-d "$body")
    fi
    raw_response=$(curl "${curl_args[@]}")
    http_code=$(echo "$raw_response" | tail -1)
    response_body=$(echo "$raw_response" | sed '$d')
  fi

  # Handle errors
  if [[ "$http_code" -ge 400 ]]; then
    echo "ERROR: HTTP $http_code" >&2
    echo "$response_body" | jq . 2>/dev/null >&2 || echo "$response_body" >&2
    return 1
  fi

  # In-memory-only mode (NO_PERSIST=1): write body to fd 3 (NOT stdout) and skip
  # all disk writes. Callers fetching short-lived secrets (e.g. registry credentials)
  # use this so plaintext never lands in .agentbase/last_response.json, on the TTY,
  # or — critically — in an LLM-visible tool-output stream.
  #
  # The caller MUST explicitly open fd 3 for writing, typically via the
  # "swap-fd" trick inside a command substitution:
  #
  #     secret_json=$(NO_PERSIST=1 api_call GET "$url" 3>&1 >/dev/null)
  #
  # If fd 3 is not open, we refuse rather than silently fall back to stdout —
  # otherwise a caller that forgot the `3>&1 >/dev/null` plumbing would leak
  # the secret to the parent's stdout (and hence into the LLM's context).
  if [ "${NO_PERSIST:-0}" = "1" ]; then
    if ! { : >&3; } 2>/dev/null; then
      echo "ERROR: NO_PERSIST=1 requires the caller to open fd 3 for writing." >&2
      echo "       Use the pattern:  \$(NO_PERSIST=1 api_call ... 3>&1 >/dev/null)" >&2
      return 1
    fi
    printf '%s\n' "$response_body" >&3
    return 0
  fi

  # Determine save path
  mkdir -p "$AGENTBASE_DIR"
  # .agentbase holds cached tokens and raw API responses (including plaintext
  # keys) — keep it out of git and images, mirroring save_env_var.sh's .env handling.
  if [ -f .gitignore ]; then
    grep -qxF '.agentbase/' .gitignore 2>/dev/null || echo '.agentbase/' >> .gitignore
  else
    echo '.agentbase/' > .gitignore
  fi
  if [ -f .dockerignore ] && ! grep -qxF '.agentbase/' .dockerignore 2>/dev/null; then
    echo '.agentbase/' >> .dockerignore
  fi
  local save_path="${SAVE_AS:-$AGENTBASE_DIR/last_response.json}"
  local save_dir
  save_dir=$(dirname "$save_path")
  [ "$save_dir" != "." ] && mkdir -p "$save_dir"

  # Always save raw response
  echo "$response_body" > "$save_path"
  # Also update last_response.json as a convenience pointer (unless SAVE_AS is last_response.json itself)
  if [ -n "${SAVE_AS:-}" ] && [ "$save_path" != "$AGENTBASE_DIR/last_response.json" ]; then
    echo "$response_body" > "$AGENTBASE_DIR/last_response.json"
  fi

  # Redact sensitive fields if specified
  if [ -n "$REDACT_FIELDS" ]; then
    echo "$response_body" | bash "$SCRIPTS_DIR/redact_response.sh" \
      --fields "$REDACT_FIELDS" \
      --save-raw "$save_path"
  else
    echo "$response_body" | jq . 2>/dev/null || echo "$response_body"
  fi
}

# --- Poll helper ---
# poll_until COMMAND CONDITION MAX_ATTEMPTS INTERVAL_SEC
# COMMAND: function name that outputs JSON
# CONDITION: jq expression that returns true/false
# Returns 0 on success, 1 on timeout
poll_until() {
  local cmd="$1"
  local condition="$2"
  local max_attempts="${3:-10}"
  local interval="${4:-3}"

  for ((i=1; i<=max_attempts; i++)); do
    local output
    if output=$($cmd 2>/dev/null); then
      if echo "$output" | jq -e "$condition" &>/dev/null; then
        echo "$output"
        return 0
      fi
    fi
    [ "$VERBOSE" = true ] && echo ">>> Poll attempt $i/$max_attempts..." >&2
    sleep "$interval"
  done
  echo "ERROR: Polling timed out after $((max_attempts * interval))s" >&2
  return 1
}

# --- Poll until HTTP 404 ---
# poll_until_gone URL MAX_ATTEMPTS INTERVAL_SEC
poll_until_gone() {
  local url="$1"
  local max_attempts="${2:-10}"
  local interval="${3:-3}"

  init_token
  for ((i=1; i<=max_attempts; i++)); do
    local code
    code=$(curl -s -o /dev/null -w '%{http_code}' -X GET "$url" \
      -H "Authorization: Bearer $TOKEN")
    if [ "$code" = "404" ]; then
      return 0
    fi
    [ "$VERBOSE" = true ] && echo ">>> Poll attempt $i/$max_attempts (HTTP $code)..." >&2
    sleep "$interval"
  done
  echo "ERROR: Resource still exists after $((max_attempts * interval))s" >&2
  return 1
}

# --- Build query string from key=value pairs ---
# build_query "page=1" "size=100" "name=foo"
# Output: ?page=1&size=100&name=foo (empty pairs are skipped)
build_query() {
  local query=""
  for param in "$@"; do
    local key="${param%%=*}"
    local val="${param#*=}"
    if [ -n "$val" ] && [ "$param" != "$key" ]; then
      [ -n "$query" ] && query+="&" || query="?"
      query+="${key}=${val}"
    fi
  done
  echo "$query"
}

# --- Build JSON body from key=value pairs ---
# build_json "name=foo" "description=bar"
# Output: {"name":"foo","description":"bar"}
build_json() {
  local args=()
  for param in "$@"; do
    local key="${param%%=*}"
    local val="${param#*=}"
    args+=(--arg "$key" "$val")
  done
  jq -n "${args[@]}" '$ARGS.named'
}

# --- Read saved response ---
# read_response [FILE]
# Read a previously saved response. Defaults to last_response.json.
# Usage:
#   SAVE_AS=".agentbase/robot_create.json" api_call POST ...
#   SECRET=$(read_response ".agentbase/robot_create.json" | jq -r '.secretKey')
read_response() {
  local file="${1:-$AGENTBASE_DIR/last_response.json}"
  if [ -f "$file" ]; then
    cat "$file"
  else
    echo "ERROR: Response file not found: $file" >&2
    return 1
  fi
}

# --- Help display ---
show_help() {
  local script_name="$1"
  local description="$2"
  local actions="$3"

  cat <<EOF
Usage: bash $script_name <action> [options]

$description

Actions:
$actions

Common flags:
  --verbose, -v   Show request/response details
  --dry-run       Show curl command without executing
  --help          Show this help message
EOF
}

# --- Resolve secret from env var or file ---
# resolve_secret RAW_VALUE ENV_NAME FILE_PATH FIELD_LABEL
# Priority: env > file > raw value
# Returns resolved value via stdout. Errors to stderr.
resolve_secret() {
  local raw="$1" env_name="$2" file_path="$3" label="${4:-secret}"

  if [ -n "$env_name" ]; then
    local val="${!env_name:-}"
    if [ -z "$val" ]; then
      echo "ERROR: Environment variable '$env_name' is not set or empty" >&2
      return 1
    fi
    echo "$val"
    return 0
  fi

  if [ -n "$file_path" ]; then
    if [ ! -f "$file_path" ]; then
      echo "ERROR: Secret file not found: $file_path" >&2
      return 1
    fi
    local val
    val=$(<"$file_path")
    val="${val%$'\n'}"  # trim trailing newline
    if [ -z "$val" ]; then
      echo "ERROR: Secret file is empty: $file_path" >&2
      return 1
    fi
    echo "$val"
    return 0
  fi

  if [ -n "$raw" ]; then
    echo "$raw"
    return 0
  fi

  echo "ERROR: No $label provided. Use --${label}, --${label}-env, or --${label}-file" >&2
  return 1
}

# Initialize
check_deps
