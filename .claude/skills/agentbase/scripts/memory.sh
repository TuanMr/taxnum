#!/usr/bin/env bash
# GreenNode AgentBase — Memory Management
# Usage: bash .claude/skills/agentbase/scripts/memory.sh <action> [options]

SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPTS_DIR/lib/config.sh"
source "$SCRIPTS_DIR/lib/common.sh"

BASE_URL="$AGENTBASE_MEMORY_URL/memories"

# --- Parse action + common flags ---
ACTION="${1:-help}"; shift 2>/dev/null || true
ARGS=()
while IFS= read -r line; do ARGS+=("$line"); done < <(parse_flags "$@")
if [ ${#ARGS[@]} -gt 0 ]; then set -- "${ARGS[@]}"; else set --; fi

# --- Actions ---

do_list() {
  local page="$DEFAULT_FIRST_PAGE"
  local size="10"

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
  local name="" description="" expiry_days=""
  local strategy_name="" strategy_type="" namespace_template="" auto_generate="false" extraction_prompt=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name) name="$2"; shift 2 ;;
      --description) description="$2"; shift 2 ;;
      --expiry-days) expiry_days="$2"; shift 2 ;;
      --strategy-name) strategy_name="$2"; shift 2 ;;
      --strategy-type) strategy_type="$2"; shift 2 ;;
      --namespace-template) namespace_template="$2"; shift 2 ;;
      --auto-generate) auto_generate="true"; shift ;;
      --extraction-prompt) extraction_prompt="$2"; shift 2 ;;
      *) echo "ERROR: Unknown option for create: $1" >&2; return 1 ;;
    esac
  done

  if [ -z "$name" ]; then
    echo "ERROR: --name is required for create" >&2; return 1
  fi
  if [ -z "$description" ]; then
    echo "ERROR: --description is required for create" >&2; return 1
  fi
  if [ -z "$expiry_days" ]; then
    echo "ERROR: --expiry-days is required for create" >&2; return 1
  fi
  if [ -z "$strategy_name" ]; then
    echo "ERROR: --strategy-name is required for create" >&2; return 1
  fi
  if [ -z "$strategy_type" ]; then
    echo "ERROR: --strategy-type is required for create" >&2; return 1
  fi

  local strategy
  strategy=$(jq -n \
    --arg sname "$strategy_name" \
    --arg stype "$strategy_type" \
    --arg nstpl "$namespace_template" \
    --arg prompt "$extraction_prompt" \
    --argjson autoGen "$auto_generate" \
    '{name: $sname, type: $stype, enableAutomaticMemoryRecordGeneration: $autoGen} +
     (if $nstpl != "" then {namespaceTemplate: $nstpl} else {} end) +
     (if $prompt != "" then {customFactExtractionPrompt: $prompt} else {} end)')

  local body
  body=$(jq -n \
    --arg name "$name" \
    --arg description "$description" \
    --argjson expiryDays "$expiry_days" \
    --argjson strategies "[$strategy]" \
    '{name: $name, description: $description, eventExpiryDuration: $expiryDays, longTermMemoryStrategies: $strategies}')

  api_call POST "$BASE_URL" "$body"
}

do_get() {
  local id="${1:-}"
  if [ -z "$id" ]; then
    echo "ERROR: ID argument is required for get" >&2; return 1
  fi
  api_call GET "${BASE_URL}/${id}"
}

do_delete() {
  local id="${1:-}"
  if [ -z "$id" ]; then
    echo "ERROR: ID argument is required for delete" >&2; return 1
  fi
  api_call DELETE "${BASE_URL}/${id}"
}

do_strategies() {
  local id="${1:-}"
  if [ -z "$id" ]; then
    echo "ERROR: ID argument is required for strategies" >&2; return 1
  fi
  api_call GET "${BASE_URL}/${id}/long-term-memory-strategies"
}

do_actors() {
  local id="${1:-}"; shift 2>/dev/null || true
  if [ -z "$id" ]; then
    echo "ERROR: ID argument is required for actors" >&2; return 1
  fi

  local page="$DEFAULT_FIRST_PAGE"
  local size="$DEFAULT_PAGE_SIZE"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --page) page="$2"; shift 2 ;;
      --size) size="$2"; shift 2 ;;
      *) echo "ERROR: Unknown option for actors: $1" >&2; return 1 ;;
    esac
  done

  local query
  query=$(build_query "page=$page" "size=$size")
  api_call GET "${BASE_URL}/${id}/actors${query}"
}

do_sessions() {
  local id="${1:-}"
  local actor_id="${2:-}"
  shift 2 2>/dev/null || true

  if [ -z "$id" ]; then
    echo "ERROR: ID argument is required for sessions" >&2; return 1
  fi
  if [ -z "$actor_id" ]; then
    echo "ERROR: ACTOR_ID argument is required for sessions" >&2; return 1
  fi

  local page="$DEFAULT_FIRST_PAGE"
  local size="$DEFAULT_PAGE_SIZE"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --page) page="$2"; shift 2 ;;
      --size) size="$2"; shift 2 ;;
      *) echo "ERROR: Unknown option for sessions: $1" >&2; return 1 ;;
    esac
  done

  local query
  query=$(build_query "page=$page" "size=$size")
  api_call GET "${BASE_URL}/${id}/actors/${actor_id}/sessions${query}"
}

# --- Events subcommands ---

do_events() {
  local sub_action="${1:-help}"; shift 2>/dev/null || true

  case "$sub_action" in
    list)   do_events_list "$@" ;;
    create) do_events_create "$@" ;;
    delete) do_events_delete "$@" ;;
    *)      echo "ERROR: Unknown events subcommand '$sub_action'. Use: list, create, delete" >&2; return 1 ;;
  esac
}

do_events_list() {
  local id="${1:-}"
  local actor_id="${2:-}"
  local session_id="${3:-}"
  shift 3 2>/dev/null || true

  if [ -z "$id" ] || [ -z "$actor_id" ] || [ -z "$session_id" ]; then
    echo "ERROR: ID, ACTOR_ID, and SESSION_ID are required for events list" >&2; return 1
  fi

  local page="$DEFAULT_FIRST_PAGE"
  local size="$DEFAULT_PAGE_SIZE"
  local from_time="" to_time=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --page) page="$2"; shift 2 ;;
      --size) size="$2"; shift 2 ;;
      --from-time) from_time="$2"; shift 2 ;;
      --to-time) to_time="$2"; shift 2 ;;
      *) echo "ERROR: Unknown option for events list: $1" >&2; return 1 ;;
    esac
  done

  local query
  query=$(build_query "page=$page" "size=$size" "fromTimestamp=$from_time" "toTimestamp=$to_time")
  api_call GET "${BASE_URL}/${id}/actors/${actor_id}/sessions/${session_id}/events${query}"
}

do_events_create() {
  local id="${1:-}"
  local actor_id="${2:-}"
  local session_id="${3:-}"
  shift 3 2>/dev/null || true

  if [ -z "$id" ] || [ -z "$actor_id" ] || [ -z "$session_id" ]; then
    echo "ERROR: ID, ACTOR_ID, and SESSION_ID are required for events create" >&2; return 1
  fi

  local type="" role="" message="" event_timestamp=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --type) type="$2"; shift 2 ;;
      --role) role="$2"; shift 2 ;;
      --message) message="$2"; shift 2 ;;
      --event-timestamp) event_timestamp="$2"; shift 2 ;;
      *) echo "ERROR: Unknown option for events create: $1" >&2; return 1 ;;
    esac
  done

  if [ -z "$type" ]; then
    echo "ERROR: --type is required for events create" >&2; return 1
  fi

  local payload
  payload=$(jq -n \
    --arg type "$type" \
    --arg role "$role" \
    --arg message "$message" \
    '{type: $type} +
     (if $role != "" then {role: $role} else {} end) +
     (if $message != "" then {message: $message} else {} end)')

  local body
  body=$(jq -n \
    --argjson payload "$payload" \
    --arg eventTimestamp "$event_timestamp" \
    '{payload: $payload} +
     (if $eventTimestamp != "" then {eventTimestamp: $eventTimestamp} else {} end)')

  api_call POST "${BASE_URL}/${id}/actors/${actor_id}/sessions/${session_id}/events" "$body"
}

do_events_delete() {
  local id="${1:-}"
  local actor_id="${2:-}"
  local session_id="${3:-}"
  local event_id="${4:-}"

  if [ -z "$id" ] || [ -z "$actor_id" ] || [ -z "$session_id" ] || [ -z "$event_id" ]; then
    echo "ERROR: ID, ACTOR_ID, SESSION_ID, and EVENT_ID are required for events delete" >&2; return 1
  fi

  api_call DELETE "${BASE_URL}/${id}/actors/${actor_id}/sessions/${session_id}/events/${event_id}"
}

# --- Records subcommands ---

do_records() {
  local sub_action="${1:-help}"; shift 2>/dev/null || true

  case "$sub_action" in
    list)                  do_records_list "$@" ;;
    search)                do_records_search "$@" ;;
    insert)                do_records_insert "$@" ;;
    delete)                do_records_delete "$@" ;;
    generate-from-session) do_records_generate_from_session "$@" ;;
    generate-from-content) do_records_generate_from_content "$@" ;;
    *)                     echo "ERROR: Unknown records subcommand '$sub_action'. Use: list, search, insert, delete, generate-from-session, generate-from-content" >&2; return 1 ;;
  esac
}

do_records_list() {
  local id="${1:-}"; shift 2>/dev/null || true
  if [ -z "$id" ]; then
    echo "ERROR: ID argument is required for records list" >&2; return 1
  fi

  local namespace="" limit="100"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --namespace) namespace="$2"; shift 2 ;;
      --limit) limit="$2"; shift 2 ;;
      *) echo "ERROR: Unknown option for records list: $1" >&2; return 1 ;;
    esac
  done

  if [ -z "$namespace" ]; then
    echo "ERROR: --namespace is required for records list" >&2; return 1
  fi

  local query
  query=$(build_query "namespace=$namespace" "limit=$limit")
  api_call GET "${BASE_URL}/${id}/memory-records${query}"
}

do_records_search() {
  local id="${1:-}"; shift 2>/dev/null || true
  if [ -z "$id" ]; then
    echo "ERROR: ID argument is required for records search" >&2; return 1
  fi

  local namespace="" query_text="" limit="" threshold=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --namespace) namespace="$2"; shift 2 ;;
      --query) query_text="$2"; shift 2 ;;
      --limit) limit="$2"; shift 2 ;;
      --threshold) threshold="$2"; shift 2 ;;
      *) echo "ERROR: Unknown option for records search: $1" >&2; return 1 ;;
    esac
  done

  if [ -z "$namespace" ]; then
    echo "ERROR: --namespace is required for records search" >&2; return 1
  fi
  if [ -z "$query_text" ]; then
    echo "ERROR: --query is required for records search" >&2; return 1
  fi

  local url_query
  url_query=$(build_query "namespace=$namespace")

  local body
  if [ -n "$limit" ] && [ -n "$threshold" ]; then
    body=$(jq -n --arg q "$query_text" --argjson l "$limit" --argjson t "$threshold" \
      '{query: $q, limit: $l, scoreThreshold: $t}')
  elif [ -n "$limit" ]; then
    body=$(jq -n --arg q "$query_text" --argjson l "$limit" \
      '{query: $q, limit: $l}')
  elif [ -n "$threshold" ]; then
    body=$(jq -n --arg q "$query_text" --argjson t "$threshold" \
      '{query: $q, scoreThreshold: $t}')
  else
    body=$(jq -n --arg q "$query_text" '{query: $q}')
  fi

  api_call POST "${BASE_URL}/${id}/memory-records:search${url_query}" "$body"
}

do_records_insert() {
  local id="${1:-}"; shift 2>/dev/null || true
  if [ -z "$id" ]; then
    echo "ERROR: ID argument is required for records insert" >&2; return 1
  fi

  local namespace="" records=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --namespace) namespace="$2"; shift 2 ;;
      --records) records="$2"; shift 2 ;;
      *) echo "ERROR: Unknown option for records insert: $1" >&2; return 1 ;;
    esac
  done

  if [ -z "$namespace" ]; then
    echo "ERROR: --namespace is required for records insert" >&2; return 1
  fi
  if [ -z "$records" ]; then
    echo "ERROR: --records is required for records insert" >&2; return 1
  fi

  local url_query
  url_query=$(build_query "namespace=$namespace")

  # Support multiple --records flags or a single JSON array string
  # If records looks like a JSON array, use it directly; otherwise treat as single record
  local records_json
  if echo "$records" | jq -e 'type == "array"' &>/dev/null; then
    records_json="$records"
  else
    # Single record string — wrap in array
    records_json=$(jq -n --arg r "$records" '[$r]')
  fi

  local body
  body=$(jq -n --argjson recs "$records_json" '{memoryRecords: $recs}')

  api_call POST "${BASE_URL}/${id}/memory-records:insert-directly${url_query}" "$body"
}

do_records_delete() {
  local id="${1:-}"
  local record_id="${2:-}"

  if [ -z "$id" ]; then
    echo "ERROR: ID argument is required for records delete" >&2; return 1
  fi
  if [ -z "$record_id" ]; then
    echo "ERROR: RECORD_ID argument is required for records delete" >&2; return 1
  fi

  api_call DELETE "${BASE_URL}/${id}/memory-records/${record_id}"
}

do_records_generate_from_session() {
  local id="${1:-}"; shift 2>/dev/null || true
  if [ -z "$id" ]; then
    echo "ERROR: ID argument is required for records generate-from-session" >&2; return 1
  fi

  local actor_id="" session_id="" strategy_id=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --actor-id) actor_id="$2"; shift 2 ;;
      --session-id) session_id="$2"; shift 2 ;;
      --strategy-id) strategy_id="$2"; shift 2 ;;
      *) echo "ERROR: Unknown option for records generate-from-session: $1" >&2; return 1 ;;
    esac
  done

  if [ -z "$actor_id" ]; then
    echo "ERROR: --actor-id is required for records generate-from-session" >&2; return 1
  fi
  if [ -z "$session_id" ]; then
    echo "ERROR: --session-id is required for records generate-from-session" >&2; return 1
  fi
  if [ -z "$strategy_id" ]; then
    echo "ERROR: --strategy-id is required for records generate-from-session" >&2; return 1
  fi

  local query
  query=$(build_query "actorId=$actor_id" "sessionId=$session_id" "longTermMemoryStrategyId=$strategy_id")
  api_call POST "${BASE_URL}/${id}/memory-records:generate-from-session${query}"
}

do_records_generate_from_content() {
  local id="${1:-}"; shift 2>/dev/null || true
  if [ -z "$id" ]; then
    echo "ERROR: ID argument is required for records generate-from-content" >&2; return 1
  fi

  local strategy_id="" actor_id="" session_id="" messages_file=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --strategy-id) strategy_id="$2"; shift 2 ;;
      --actor-id) actor_id="$2"; shift 2 ;;
      --session-id) session_id="$2"; shift 2 ;;
      --messages-file) messages_file="$2"; shift 2 ;;
      *) echo "ERROR: Unknown option for records generate-from-content: $1" >&2; return 1 ;;
    esac
  done

  if [ -z "$strategy_id" ]; then
    echo "ERROR: --strategy-id is required for records generate-from-content" >&2; return 1
  fi
  if [ -z "$messages_file" ]; then
    echo "ERROR: --messages-file is required for records generate-from-content" >&2; return 1
  fi
  if [ ! -f "$messages_file" ]; then
    echo "ERROR: Messages file not found: $messages_file" >&2; return 1
  fi

  local query
  query=$(build_query "longTermMemoryStrategyId=$strategy_id" "actorId=$actor_id" "sessionId=$session_id")

  local body
  if ! body=$(jq -c '{chatMessages: .}' "$messages_file" 2>/dev/null); then
    echo "ERROR: Invalid JSON or read error in $messages_file" >&2; return 1
  fi

  api_call POST "${BASE_URL}/${id}/memory-records:generate-from-content${query}" "$body"
}

do_help() {
  show_help ".claude/skills/agentbase/scripts/memory.sh" \
    "Manage GreenNode AgentBase Memory resources." \
    "  list       [--page N] [--size N]                        List memories
  create     --name NAME --description DESC --expiry-days N --strategy-name SNAME --strategy-type TYPE
               [--namespace-template TPL] [--auto-generate] [--extraction-prompt TEXT]
                                                              Create a new memory
  get        ID                                               Get memory by ID
  delete     ID                                               Delete a memory
  strategies ID                                               List long-term memory strategies
  actors     ID [--page N] [--size N]                         List actors for a memory
  sessions   ID ACTOR_ID [--page N] [--size N]                List sessions for an actor
  events     list ID ACTOR_ID SESSION_ID [--page N] [--size N] [--from-time ISO] [--to-time ISO]
                                                              List events for a session
  events     create ID ACTOR_ID SESSION_ID --type TYPE [--role ROLE] [--message TEXT]
                                                              Create an event
  events     delete ID ACTOR_ID SESSION_ID EVENT_ID           Delete an event
  records    list ID --namespace NS [--limit N]               List memory records
  records    search ID --namespace NS --query TEXT [--limit N] [--threshold F]
                                                              Search memory records
  records    insert ID --namespace NS --records 'JSON_ARRAY_OR_SINGLE_STRING'
                                                              Insert memory records
  records    delete ID RECORD_ID                              Delete a memory record
  records    generate-from-session ID --actor-id AID --session-id SID --strategy-id STID
                                                              Generate records from session
  records    generate-from-content ID --strategy-id STID [--actor-id AID] [--session-id SID] --messages-file PATH
                                                              Generate records from content
  help                                                        Show this help message"
}

# --- Dispatch ---
case "$ACTION" in
  list)       do_list "$@" ;;
  create)     do_create "$@" ;;
  get)        do_get "$@" ;;
  delete)     do_delete "$@" ;;
  strategies) do_strategies "$@" ;;
  actors)     do_actors "$@" ;;
  sessions)   do_sessions "$@" ;;
  events)     do_events "$@" ;;
  records)    do_records "$@" ;;
  help)       do_help ;;
  *)          echo "ERROR: Unknown action '$ACTION'. Run with 'help' for usage." >&2; exit 1 ;;
esac
