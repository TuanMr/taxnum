#!/usr/bin/env bash
# GreenNode AgentBase — Agent Identity Management
# Usage: bash .claude/skills/agentbase/scripts/identity.sh <action> [options]

SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPTS_DIR/lib/config.sh"
source "$SCRIPTS_DIR/lib/common.sh"

BASE_URL="$AGENTBASE_IDENTITY_URL/agent-identities"

# --- Parse action + common flags ---
ACTION="${1:-help}"; shift 2>/dev/null || true
ARGS=()
while IFS= read -r line; do ARGS+=("$line"); done < <(parse_flags "$@")
if [ ${#ARGS[@]} -gt 0 ]; then set -- "${ARGS[@]}"; else set --; fi

# --- Actions ---

do_list() {
  local page="$IDENTITY_FIRST_PAGE"
  local size="$DEFAULT_PAGE_SIZE"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --page) page="$2"; shift 2 ;;
      --size) size="$2"; shift 2 ;;
      *) echo "ERROR: Unknown option for list: $1" >&2; return 1 ;;
    esac
  done

  local query
  query=$(build_query "page=$page" "size=$size")
  api_call GET "${BASE_URL}${query}"
}

do_create() {
  local name="" description="" allowed_urls=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name) name="$2"; shift 2 ;;
      --description) description="$2"; shift 2 ;;
      --allowed-urls) allowed_urls="$2"; shift 2 ;;
      *) echo "ERROR: Unknown option for create: $1" >&2; return 1 ;;
    esac
  done

  if [ -z "$name" ]; then
    echo "ERROR: --name is required for create" >&2
    return 1
  fi

  local body
  if [ -n "$allowed_urls" ]; then
    # Build JSON with allowedReturnUrls as an array
    local urls_json
    urls_json=$(echo "$allowed_urls" | tr ',' '\n' | jq -R . | jq -s .)
    body=$(jq -n \
      --arg name "$name" \
      --arg description "$description" \
      --argjson allowedReturnUrls "$urls_json" \
      '{name: $name} +
       (if $description != "" then {description: $description} else {} end) +
       {allowedReturnUrls: $allowedReturnUrls}')
  elif [ -n "$description" ]; then
    body=$(build_json "name=$name" "description=$description")
  else
    body=$(build_json "name=$name")
  fi

  api_call POST "$BASE_URL" "$body"
}

do_get() {
  local name="${1:-}"
  if [ -z "$name" ]; then
    echo "ERROR: Name argument is required for get" >&2
    return 1
  fi
  api_call GET "${BASE_URL}/${name}"
}

do_update() {
  local name="${1:-}"; shift 2>/dev/null || true
  if [ -z "$name" ]; then
    echo "ERROR: Name argument is required for update" >&2
    return 1
  fi

  local description="" allowed_urls="" has_description=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --description) description="$2"; has_description=true; shift 2 ;;
      --allowed-urls) allowed_urls="$2"; shift 2 ;;
      *) echo "ERROR: Unknown option for update: $1" >&2; return 1 ;;
    esac
  done

  local body
  if [ -n "$allowed_urls" ]; then
    local urls_json
    urls_json=$(echo "$allowed_urls" | tr ',' '\n' | jq -R . | jq -s .)
    body=$(jq -n \
      --arg description "$description" \
      --argjson allowedReturnUrls "$urls_json" \
      --argjson hasDescription "$has_description" \
      '(if $hasDescription then {description: $description} else {} end) +
       {allowedReturnUrls: $allowedReturnUrls}')
  elif [ "$has_description" = true ]; then
    body=$(jq -n --arg description "$description" '{description: $description}')
  else
    echo "ERROR: At least one of --description or --allowed-urls is required for update" >&2
    return 1
  fi

  api_call PUT "${BASE_URL}/${name}" "$body"
}

do_delete() {
  local name="${1:-}"
  if [ -z "$name" ]; then
    echo "ERROR: Name argument is required for delete" >&2
    return 1
  fi
  api_call DELETE "${BASE_URL}/${name}"
}

do_help() {
  show_help ".claude/skills/agentbase/scripts/identity.sh" \
    "Manage GreenNode AgentBase Agent Identities." \
    "  list   [--page N] [--size N]                          List agent identities
  create --name NAME [--description DESC] [--allowed-urls URL1,URL2]
                                                           Create a new agent identity
  get    NAME                                              Get agent identity by name
  update NAME [--description DESC] [--allowed-urls URL1,URL2]
                                                           Update an agent identity
  delete NAME                                              Delete an agent identity
  help                                                     Show this help message"
}

# --- Dispatch ---
case "$ACTION" in
  list)   do_list "$@" ;;
  create) do_create "$@" ;;
  get)    do_get "$@" ;;
  update) do_update "$@" ;;
  delete) do_delete "$@" ;;
  help)   do_help ;;
  *)      echo "ERROR: Unknown action '$ACTION'. Run with 'help' for usage." >&2; exit 1 ;;
esac
