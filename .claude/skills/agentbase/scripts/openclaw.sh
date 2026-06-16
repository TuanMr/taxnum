#!/usr/bin/env bash
# GreenNode AgentBase — OpenClaw Management
# Manage pre-built (template-based) OpenClaw agents on the Runtime Service.
# These are platform-provided agents (e.g. Telegram/Zalo bots) created from
# a versioned template — distinct from Custom Agents (/agent-runtimes) which
# the user builds and packages as their own Docker image.
#
# Usage: bash .claude/skills/agentbase/scripts/openclaw.sh <action> [options]

SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPTS_DIR/lib/config.sh"
source "$SCRIPTS_DIR/lib/common.sh"

BASE_URL="$AGENTBASE_RUNTIME_URL/openclaws"
VERSIONS_URL="$AGENTBASE_RUNTIME_URL/openclaw-versions"

# --- Parse action + common flags ---
ACTION="${1:-help}"; shift 2>/dev/null || true
ARGS=()
while IFS= read -r line; do ARGS+=("$line"); done < <(parse_flags "$@")
if [ ${#ARGS[@]} -gt 0 ]; then set -- "${ARGS[@]}"; else set --; fi

# --- Helpers ---

# Read env file and convert to JSON object {"KEY": "VALUE", ...}
read_env_file() {
  local env_file="$1"
  if [ ! -f "$env_file" ]; then
    echo "ERROR: Env file not found: $env_file" >&2
    return 1
  fi
  jq -Rn '[inputs | select(test("^\\s*#") | not) | select(length > 0) |
    capture("^(?<key>[^=]+)=(?<val>.*)$")] |
    map({(.key): .val}) | add // {}' < "$env_file"
}

# Build a channel JSON object from a JSON file or flag-style spec.
# Expected file shape: {"botToken": "...", "dmPolicy": "pairing|allowlist",
#                       "dmAllowedUserIds": ["...", ...] }
build_channel_from_file() {
  local file="$1"
  if [ ! -f "$file" ]; then
    echo "ERROR: Channel config file not found: $file" >&2
    return 1
  fi
  jq '{botToken: (.botToken // empty),
       dmPolicy: (.dmPolicy // "pairing"),
       dmAllowedUserIds: (.dmAllowedUserIds // [])}' "$file"
}

# --- Actions ---

do_list() {
  local page="$DEFAULT_FIRST_PAGE"
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
  REDACT_FIELDS="gatewayToken,botToken" api_call GET "${BASE_URL}${query}"
}

do_create() {
  local name="" version_id="" flavor_id="" env_file=""
  local maas_enabled="" maas_api_key_name=""
  local telegram_channel_file="" zalo_channel_file=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name) name="$2"; shift 2 ;;
      --version-id) version_id="$2"; shift 2 ;;
      --flavor) flavor_id="$2"; shift 2 ;;
      --env-file) env_file="$2"; shift 2 ;;
      --maas-enabled) maas_enabled="$2"; shift 2 ;;
      --maas-api-key-name) maas_api_key_name="$2"; shift 2 ;;
      --telegram-channel-file) telegram_channel_file="$2"; shift 2 ;;
      --zalo-channel-file) zalo_channel_file="$2"; shift 2 ;;
      *) echo "ERROR: Unknown option for create: $1" >&2; return 1 ;;
    esac
  done

  # Build environment variables JSON
  local env_json="{}"
  if [ -n "$env_file" ]; then
    env_json=$(read_env_file "$env_file") || return 1
  fi

  # Build channels JSON (omit channels object entirely if no channel provided)
  local channels_json="null"
  local telegram_json="null" zalo_json="null"
  if [ -n "$telegram_channel_file" ]; then
    telegram_json=$(build_channel_from_file "$telegram_channel_file") || return 1
  fi
  if [ -n "$zalo_channel_file" ]; then
    zalo_json=$(build_channel_from_file "$zalo_channel_file") || return 1
  fi
  if [ "$telegram_json" != "null" ] || [ "$zalo_json" != "null" ]; then
    channels_json=$(jq -n \
      --argjson telegram "$telegram_json" \
      --argjson zalo "$zalo_json" \
      '{} +
       (if $telegram != null then {telegram: $telegram} else {} end) +
       (if $zalo != null then {zalo: $zalo} else {} end)')
  fi

  # Build greenNodeModelProvider object only if user opted in
  local maas_json="null"
  if [ "$maas_enabled" = "true" ]; then
    maas_json=$(jq -n \
      --arg apiKeyName "${maas_api_key_name:-}" \
      '{enabled: true} +
       (if $apiKeyName != "" then {apiKeyName: $apiKeyName} else {} end)')
  elif [ "$maas_enabled" = "false" ]; then
    maas_json='{"enabled": false}'
  fi

  # Build base payload
  local body
  body=$(jq -n \
    --arg name "$name" \
    --arg versionId "$version_id" \
    --arg flavorId "$flavor_id" \
    --argjson environmentVariables "$env_json" \
    --argjson channels "$channels_json" \
    --argjson greenNodeModelProvider "$maas_json" \
    '{environmentVariables: $environmentVariables} +
     (if $name != "" then {name: $name} else {} end) +
     (if $versionId != "" then {versionId: $versionId} else {} end) +
     (if $flavorId != "" then {flavorId: $flavorId} else {} end) +
     (if $channels != null then {channels: $channels} else {} end) +
     (if $greenNodeModelProvider != null then {greenNodeModelProvider: $greenNodeModelProvider} else {} end)')

  REDACT_FIELDS="gatewayToken,botToken,apiKey" api_call POST "$BASE_URL" "$body"
}

do_get() {
  local id="${1:-}"
  if [ -z "$id" ]; then
    echo "ERROR: OpenClaw ID is required for get" >&2; return 1
  fi
  REDACT_FIELDS="gatewayToken,botToken" api_call GET "${BASE_URL}/${id}"
}

do_delete() {
  local id="${1:-}"
  if [ -z "$id" ]; then
    echo "ERROR: OpenClaw ID is required for delete" >&2; return 1
  fi
  api_call DELETE "${BASE_URL}/${id}"
}

do_start() {
  local id="${1:-}"
  if [ -z "$id" ]; then
    echo "ERROR: OpenClaw ID is required for start" >&2; return 1
  fi
  api_call POST "${BASE_URL}/${id}/start"
}

do_stop() {
  local id="${1:-}"
  if [ -z "$id" ]; then
    echo "ERROR: OpenClaw ID is required for stop" >&2; return 1
  fi
  api_call POST "${BASE_URL}/${id}/stop"
}

do_update_version() {
  local id="${1:-}"; shift 2>/dev/null || true
  if [ -z "$id" ]; then
    echo "ERROR: OpenClaw ID is required for update-version" >&2; return 1
  fi

  local version_id=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --version-id) version_id="$2"; shift 2 ;;
      *) echo "ERROR: Unknown option for update-version: $1" >&2; return 1 ;;
    esac
  done

  if [ -z "$version_id" ]; then
    echo "ERROR: --version-id is required for update-version" >&2; return 1
  fi

  local query
  query=$(build_query "versionId=$version_id")
  api_call PATCH "${BASE_URL}/${id}/version${query}"
}

do_versions() {
  api_call GET "$VERSIONS_URL"
}

do_help() {
  show_help ".claude/skills/agentbase/scripts/openclaw.sh" \
    "Manage GreenNode AgentBase OpenClaw agents (pre-built / template-based)." \
    "  list   [--page N] [--size N]                                List OpenClaws
  create [--name NAME] [--version-id ID] [--flavor ID]
         [--env-file PATH]
         [--maas-enabled true|false] [--maas-api-key-name NAME]
         [--telegram-channel-file PATH] [--zalo-channel-file PATH]
                                                                  Create a new OpenClaw
                                                                  (name auto-generated if omitted;
                                                                   default versionId / flavor 2x4-general are
                                                                   selected server-side when not provided)
  get    ID                                                       Get OpenClaw by ID
  delete ID                                                       Delete an OpenClaw
  start  ID                                                       Start a stopped OpenClaw
  stop   ID                                                       Stop a running OpenClaw
  update-version ID --version-id ID                               Switch OpenClaw to a different version
  versions                                                        List available OpenClaw versions
  help                                                            Show this help message

Channel file format (JSON):
  {
    \"botToken\": \"...\",
    \"dmPolicy\": \"pairing\" | \"allowlist\",
    \"dmAllowedUserIds\": [\"user-id-1\", ...]
  }
  - dmPolicy=allowlist requires a non-empty dmAllowedUserIds list."
}

# --- Dispatch ---
case "$ACTION" in
  list)            do_list "$@" ;;
  create)          do_create "$@" ;;
  get)             do_get "$@" ;;
  delete)          do_delete "$@" ;;
  start)           do_start "$@" ;;
  stop)            do_stop "$@" ;;
  update-version)  do_update_version "$@" ;;
  versions)        do_versions ;;
  help)            do_help ;;
  *)               echo "ERROR: Unknown action '$ACTION'. Run with 'help' for usage." >&2; exit 1 ;;
esac
