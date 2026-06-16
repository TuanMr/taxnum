#!/usr/bin/env bash
# GreenNode AgentBase — Outbound Auth Provider Management
# Usage: bash .claude/skills/agentbase/scripts/auth.sh <type> <action> [options]
#   type: apikey, oauth2, delegated

SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPTS_DIR/lib/config.sh"
source "$SCRIPTS_DIR/lib/common.sh"

BASE_URL="$AGENTBASE_IDENTITY_URL/outbound-auth"

# ─── API Key Provider ────────────────────────────────────────────────────────

apikey_list() {
  local page="$IDENTITY_FIRST_PAGE" size="$DEFAULT_PAGE_SIZE" sort_by="" sort_dir=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --page) page="$2"; shift 2 ;;
      --size) size="$2"; shift 2 ;;
      --sort-by) sort_by="$2"; shift 2 ;;
      --sort-direction) sort_dir="$2"; shift 2 ;;
      *) echo "ERROR: Unknown option: $1" >&2; return 1 ;;
    esac
  done
  local query
  query=$(build_query "page=$page" "size=$size" "sortBy=$sort_by" "sortDirection=$sort_dir")
  api_call GET "${BASE_URL}/api-key-providers${query}"
}

apikey_create() {
  local name="" apikey="" apikey_env="" apikey_file=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name) name="$2"; shift 2 ;;
      --apikey) apikey="$2"; shift 2 ;;
      --apikey-env) apikey_env="$2"; shift 2 ;;
      --apikey-file) apikey_file="$2"; shift 2 ;;
      *) echo "ERROR: Unknown option: $1" >&2; return 1 ;;
    esac
  done
  if [ -z "$name" ]; then
    echo "ERROR: --name is required" >&2
    return 1
  fi
  local resolved_key
  resolved_key=$(resolve_secret "$apikey" "$apikey_env" "$apikey_file" "apikey") || return 1
  local body
  body=$(build_json "name=$name" "apikey=$resolved_key")
  api_call POST "${BASE_URL}/api-key-providers" "$body"
}

apikey_get() {
  local name=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name) name="$2"; shift 2 ;;
      *) echo "ERROR: Unknown option: $1" >&2; return 1 ;;
    esac
  done
  if [ -z "$name" ]; then
    echo "ERROR: --name is required" >&2
    return 1
  fi
  api_call GET "${BASE_URL}/api-key-providers/${name}"
}

apikey_update() {
  local name="" apikey="" apikey_env="" apikey_file=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name) name="$2"; shift 2 ;;
      --apikey) apikey="$2"; shift 2 ;;
      --apikey-env) apikey_env="$2"; shift 2 ;;
      --apikey-file) apikey_file="$2"; shift 2 ;;
      *) echo "ERROR: Unknown option: $1" >&2; return 1 ;;
    esac
  done
  if [ -z "$name" ]; then
    echo "ERROR: --name is required" >&2
    return 1
  fi
  local resolved_key
  resolved_key=$(resolve_secret "$apikey" "$apikey_env" "$apikey_file" "apikey") || return 1
  local body
  body=$(build_json "apikey=$resolved_key")
  api_call PUT "${BASE_URL}/api-key-providers/${name}" "$body"
}

apikey_delete() {
  local name=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name) name="$2"; shift 2 ;;
      *) echo "ERROR: Unknown option: $1" >&2; return 1 ;;
    esac
  done
  if [ -z "$name" ]; then
    echo "ERROR: --name is required" >&2
    return 1
  fi
  api_call DELETE "${BASE_URL}/api-key-providers/${name}"
}

apikey_get_key() {
  local provider="" identity=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --provider) provider="$2"; shift 2 ;;
      --identity) identity="$2"; shift 2 ;;
      *) echo "ERROR: Unknown option: $1" >&2; return 1 ;;
    esac
  done
  if [ -z "$provider" ] || [ -z "$identity" ]; then
    echo "ERROR: --provider and --identity are required" >&2
    return 1
  fi
  api_call GET "${BASE_URL}/api-key-providers/${provider}/agent-identities/${identity}/api-key"
}

# ─── OAuth2 Provider ─────────────────────────────────────────────────────────

oauth2_list() {
  local page="$IDENTITY_FIRST_PAGE" size="$DEFAULT_PAGE_SIZE" sort_by="" sort_dir=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --page) page="$2"; shift 2 ;;
      --size) size="$2"; shift 2 ;;
      --sort-by) sort_by="$2"; shift 2 ;;
      --sort-direction) sort_dir="$2"; shift 2 ;;
      *) echo "ERROR: Unknown option: $1" >&2; return 1 ;;
    esac
  done
  local query
  query=$(build_query "page=$page" "size=$size" "sortBy=$sort_by" "sortDirection=$sort_dir")
  api_call GET "${BASE_URL}/oauth2-providers${query}"
}

oauth2_create() {
  local name="" client_id="" client_secret="" client_secret_env="" client_secret_file="" auth_url="" token_url=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name) name="$2"; shift 2 ;;
      --client-id) client_id="$2"; shift 2 ;;
      --client-secret) client_secret="$2"; shift 2 ;;
      --client-secret-env) client_secret_env="$2"; shift 2 ;;
      --client-secret-file) client_secret_file="$2"; shift 2 ;;
      --authorization-url) auth_url="$2"; shift 2 ;;
      --token-url) token_url="$2"; shift 2 ;;
      *) echo "ERROR: Unknown option: $1" >&2; return 1 ;;
    esac
  done
  if [ -z "$name" ] || [ -z "$client_id" ] || [ -z "$auth_url" ] || [ -z "$token_url" ]; then
    echo "ERROR: --name, --client-id, --authorization-url, and --token-url are required" >&2
    return 1
  fi
  local resolved_secret
  resolved_secret=$(resolve_secret "$client_secret" "$client_secret_env" "$client_secret_file" "client-secret") || return 1
  local body
  body=$(jq -n \
    --arg name "$name" \
    --arg clientId "$client_id" \
    --arg clientSecret "$resolved_secret" \
    --arg authorizationUrl "$auth_url" \
    --arg tokenUrl "$token_url" \
    '{name: $name, clientId: $clientId, clientSecret: $clientSecret, authorizationUrl: $authorizationUrl, tokenUrl: $tokenUrl}')
  api_call POST "${BASE_URL}/oauth2-providers" "$body"
}

oauth2_get() {
  local name=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name) name="$2"; shift 2 ;;
      *) echo "ERROR: Unknown option: $1" >&2; return 1 ;;
    esac
  done
  if [ -z "$name" ]; then
    echo "ERROR: --name is required" >&2
    return 1
  fi
  api_call GET "${BASE_URL}/oauth2-providers/${name}"
}

oauth2_update() {
  local name="" client_id="" client_secret="" client_secret_env="" client_secret_file="" auth_url="" token_url=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name) name="$2"; shift 2 ;;
      --client-id) client_id="$2"; shift 2 ;;
      --client-secret) client_secret="$2"; shift 2 ;;
      --client-secret-env) client_secret_env="$2"; shift 2 ;;
      --client-secret-file) client_secret_file="$2"; shift 2 ;;
      --authorization-url) auth_url="$2"; shift 2 ;;
      --token-url) token_url="$2"; shift 2 ;;
      *) echo "ERROR: Unknown option: $1" >&2; return 1 ;;
    esac
  done
  if [ -z "$name" ]; then
    echo "ERROR: --name is required" >&2
    return 1
  fi

  # Resolve client secret from env/file if provided
  if [ -n "$client_secret_env" ] || [ -n "$client_secret_file" ]; then
    client_secret=$(resolve_secret "$client_secret" "$client_secret_env" "$client_secret_file" "client-secret") || return 1
  fi

  # PUT requires ALL 4 fields. Fetch current values to merge with provided updates.
  # REDACT_FIELDS="" is intentional: we need the raw clientSecret for the merge.
  # The response is captured in a local variable (never displayed).
  local current
  current=$(REDACT_FIELDS="" api_call GET "${BASE_URL}/oauth2-providers/${name}" 2>/dev/null) || {
    echo "ERROR: Failed to fetch existing OAuth2 provider '$name' for merge" >&2
    return 1
  }

  # Merge: use provided values, fall back to existing
  [ -z "$client_id" ] && client_id=$(echo "$current" | jq -r '.clientId // empty')
  [ -z "$client_secret" ] && client_secret=$(echo "$current" | jq -r '.clientSecret // empty')
  [ -z "$auth_url" ] && auth_url=$(echo "$current" | jq -r '.authorizationUrl // empty')
  [ -z "$token_url" ] && token_url=$(echo "$current" | jq -r '.tokenUrl // empty')

  if [ -z "$client_id" ] || [ -z "$client_secret" ] || [ -z "$auth_url" ] || [ -z "$token_url" ]; then
    echo "ERROR: Could not resolve all required fields (clientId, clientSecret, authorizationUrl, tokenUrl). Provide missing fields explicitly." >&2
    return 1
  fi

  local body
  body=$(jq -n \
    --arg clientId "$client_id" \
    --arg clientSecret "$client_secret" \
    --arg authorizationUrl "$auth_url" \
    --arg tokenUrl "$token_url" \
    '{clientId: $clientId, clientSecret: $clientSecret, authorizationUrl: $authorizationUrl, tokenUrl: $tokenUrl}')
  api_call PUT "${BASE_URL}/oauth2-providers/${name}" "$body"
}

oauth2_delete() {
  local name=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name) name="$2"; shift 2 ;;
      *) echo "ERROR: Unknown option: $1" >&2; return 1 ;;
    esac
  done
  if [ -z "$name" ]; then
    echo "ERROR: --name is required" >&2
    return 1
  fi
  api_call DELETE "${BASE_URL}/oauth2-providers/${name}"
}

oauth2_get_m2m_token() {
  local provider="" identity="" scopes=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --provider) provider="$2"; shift 2 ;;
      --identity) identity="$2"; shift 2 ;;
      --scopes) scopes="$2"; shift 2 ;;
      *) echo "ERROR: Unknown option: $1" >&2; return 1 ;;
    esac
  done
  if [ -z "$provider" ] || [ -z "$identity" ]; then
    echo "ERROR: --provider and --identity are required" >&2
    return 1
  fi
  if [ -z "$scopes" ]; then
    echo "ERROR: --scopes is required for m2m token (at least one scope)" >&2
    return 1
  fi

  local body
  body=$(echo "$scopes" | jq -R 'split(",")' | jq '{scopes: .}')
  api_call POST "${BASE_URL}/oauth2-providers/${provider}/agent-identities/${identity}/tokens/m2m" "$body"
}

oauth2_get_3lo_token() {
  local provider="" identity="" agent_user_id="" return_url="" scopes=""
  local session_id="" custom_params="" custom_state="" force_auth=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --provider) provider="$2"; shift 2 ;;
      --identity) identity="$2"; shift 2 ;;
      --agent-user-id) agent_user_id="$2"; shift 2 ;;
      --return-url) return_url="$2"; shift 2 ;;
      --scopes) scopes="$2"; shift 2 ;;
      --session-id) session_id="$2"; shift 2 ;;
      --custom-parameters) custom_params="$2"; shift 2 ;;
      --custom-state) custom_state="$2"; shift 2 ;;
      --force-authentication) force_auth="$2"; shift 2 ;;
      *) echo "ERROR: Unknown option: $1" >&2; return 1 ;;
    esac
  done
  if [ -z "$provider" ] || [ -z "$identity" ] || [ -z "$agent_user_id" ] || [ -z "$return_url" ]; then
    echo "ERROR: --provider, --identity, --agent-user-id, and --return-url are required" >&2
    return 1
  fi
  local scopes_json="[]"
  [ -n "$scopes" ] && scopes_json=$(echo "$scopes" | jq -R 'split(",")')
  local body
  body=$(jq -n \
    --arg agentUserId "$agent_user_id" \
    --arg returnUrl "$return_url" \
    --argjson scopes "$scopes_json" \
    '{agentUserId: $agentUserId, returnUrl: $returnUrl, scopes: $scopes}')
  [ -n "$session_id" ] && body=$(echo "$body" | jq --arg v "$session_id" '. + {sessionId: $v}')
  [ -n "$custom_params" ] && body=$(echo "$body" | jq --argjson v "$custom_params" '. + {customParameters: $v}')
  [ -n "$custom_state" ] && body=$(echo "$body" | jq --arg v "$custom_state" '. + {customState: $v}')
  [ -n "$force_auth" ] && body=$(echo "$body" | jq --argjson v "$force_auth" '. + {forceAuthentication: $v}')
  api_call POST "${BASE_URL}/oauth2-providers/${provider}/agent-identities/${identity}/tokens/3lo" "$body"
}

# ─── Delegated API Key Provider ──────────────────────────────────────────────

delegated_list() {
  local page="$IDENTITY_FIRST_PAGE" size="$DEFAULT_PAGE_SIZE" sort_by="" sort_dir=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --page) page="$2"; shift 2 ;;
      --size) size="$2"; shift 2 ;;
      --sort-by) sort_by="$2"; shift 2 ;;
      --sort-direction) sort_dir="$2"; shift 2 ;;
      *) echo "ERROR: Unknown option: $1" >&2; return 1 ;;
    esac
  done
  local query
  query=$(build_query "page=$page" "size=$size" "sortBy=$sort_by" "sortDirection=$sort_dir")
  api_call GET "${BASE_URL}/delegated-api-key-providers${query}"
}

delegated_create() {
  local name=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name) name="$2"; shift 2 ;;
      *) echo "ERROR: Unknown option: $1" >&2; return 1 ;;
    esac
  done
  if [ -z "$name" ]; then
    echo "ERROR: --name is required" >&2
    return 1
  fi
  local body
  body=$(build_json "name=$name")
  api_call POST "${BASE_URL}/delegated-api-key-providers" "$body"
}

delegated_get() {
  local name=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name) name="$2"; shift 2 ;;
      *) echo "ERROR: Unknown option: $1" >&2; return 1 ;;
    esac
  done
  if [ -z "$name" ]; then
    echo "ERROR: --name is required" >&2
    return 1
  fi
  api_call GET "${BASE_URL}/delegated-api-key-providers/${name}"
}

delegated_delete() {
  local name=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name) name="$2"; shift 2 ;;
      *) echo "ERROR: Unknown option: $1" >&2; return 1 ;;
    esac
  done
  if [ -z "$name" ]; then
    echo "ERROR: --name is required" >&2
    return 1
  fi
  api_call DELETE "${BASE_URL}/delegated-api-key-providers/${name}"
}

delegated_get_key() {
  local provider="" identity="" agent_user_id="" return_url=""
  local custom_state="" session_id="" force_delegation=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --provider) provider="$2"; shift 2 ;;
      --identity) identity="$2"; shift 2 ;;
      --agent-user-id) agent_user_id="$2"; shift 2 ;;
      --return-url) return_url="$2"; shift 2 ;;
      --custom-state) custom_state="$2"; shift 2 ;;
      --session-id) session_id="$2"; shift 2 ;;
      --force-delegation) force_delegation="$2"; shift 2 ;;
      *) echo "ERROR: Unknown option: $1" >&2; return 1 ;;
    esac
  done
  if [ -z "$provider" ] || [ -z "$identity" ] || [ -z "$agent_user_id" ] || [ -z "$return_url" ]; then
    echo "ERROR: --provider, --identity, --agent-user-id, and --return-url are required" >&2
    return 1
  fi
  local body
  body=$(jq -n \
    --arg agentUserId "$agent_user_id" \
    --arg returnUrl "$return_url" \
    '{agentUserId: $agentUserId, returnUrl: $returnUrl}')
  [ -n "$custom_state" ] && body=$(echo "$body" | jq --arg v "$custom_state" '. + {customState: $v}')
  [ -n "$session_id" ] && body=$(echo "$body" | jq --arg v "$session_id" '. + {sessionId: $v}')
  [ -n "$force_delegation" ] && body=$(echo "$body" | jq --argjson v "$force_delegation" '. + {forceDelegation: $v}')
  api_call POST "${BASE_URL}/delegated-api-key-providers/${provider}/agent-identities/${identity}/api-key" "$body"
}

# ─── Help ────────────────────────────────────────────────────────────────────

show_auth_help() {
  cat <<'EOF'
Usage: bash .claude/skills/agentbase/scripts/auth.sh <type> <action> [options]

Manage GreenNode AgentBase Outbound Auth Providers.

Types & Actions:
  apikey list          [--page N] [--size N] [--sort-by FIELD] [--sort-direction ASC|DESC]
  apikey create        --name NAME (--apikey KEY | --apikey-env ENV_VAR | --apikey-file PATH)
  apikey get           --name NAME
  apikey update        --name NAME (--apikey KEY | --apikey-env ENV_VAR | --apikey-file PATH)
  apikey delete        --name NAME
  apikey get-key       --provider NAME --identity NAME

  oauth2 list          [--page N] [--size N] [--sort-by FIELD] [--sort-direction ASC|DESC]
  oauth2 create        --name NAME --client-id ID (--client-secret SECRET | --client-secret-env ENV_VAR | --client-secret-file PATH) --authorization-url URL --token-url URL
  oauth2 get           --name NAME
  oauth2 update        --name NAME [--client-id ID] [--client-secret SECRET | --client-secret-env ENV_VAR | --client-secret-file PATH] [--authorization-url URL] [--token-url URL]
  oauth2 delete        --name NAME
  oauth2 get-m2m-token --provider NAME --identity NAME --scopes s1,s2
  oauth2 get-3lo-token --provider NAME --identity NAME --agent-user-id UID --return-url URL [--scopes s1,s2] [--session-id ID] [--custom-parameters P] [--custom-state S] [--force-authentication true|false]

  delegated list       [--page N] [--size N] [--sort-by FIELD] [--sort-direction ASC|DESC]
  delegated create     --name NAME
  delegated get        --name NAME
  delegated delete     --name NAME
  delegated get-key    --provider NAME --identity NAME --agent-user-id UID --return-url URL [--custom-state S] [--session-id ID] [--force-delegation true|false]

Common flags:
  --verbose, -v   Show request/response details
  --dry-run       Show curl command without executing
  --redact FIELDS Redact fields in response (comma-separated)
  --help          Show this help message
EOF
}

# ─── Main dispatcher ─────────────────────────────────────────────────────────

main() {
  if [[ $# -lt 1 ]]; then
    show_auth_help
    exit 1
  fi

  local provider_type="$1"; shift

  if [[ "$provider_type" == "help" || "$provider_type" == "--help" ]]; then
    show_auth_help
    exit 0
  fi

  if [[ $# -lt 1 ]]; then
    echo "ERROR: Action required. Run with 'help' for usage." >&2
    exit 1
  fi

  local action="$1"; shift

  # Parse common flags, get remaining args
  local args=()
  while IFS= read -r line; do
    args+=("$line")
  done < <(parse_flags "$@")

  case "$provider_type" in
    apikey)
      [ -z "$REDACT_FIELDS" ] && REDACT_FIELDS="apikey"
      case "$action" in
        list)          apikey_list "${args[@]+"${args[@]}"}" ;;
        create)        apikey_create "${args[@]+"${args[@]}"}" ;;
        get)           apikey_get "${args[@]+"${args[@]}"}" ;;
        update)        apikey_update "${args[@]+"${args[@]}"}" ;;
        delete)        apikey_delete "${args[@]+"${args[@]}"}" ;;
        get-key)       apikey_get_key "${args[@]+"${args[@]}"}" ;;
        *)             echo "ERROR: Unknown apikey action '$action'" >&2; exit 1 ;;
      esac
      ;;
    oauth2)
      [ -z "$REDACT_FIELDS" ] && REDACT_FIELDS="clientSecret,accessToken"
      case "$action" in
        list)          oauth2_list "${args[@]+"${args[@]}"}" ;;
        create)        oauth2_create "${args[@]+"${args[@]}"}" ;;
        get)           oauth2_get "${args[@]+"${args[@]}"}" ;;
        update)        oauth2_update "${args[@]+"${args[@]}"}" ;;
        delete)        oauth2_delete "${args[@]+"${args[@]}"}" ;;
        get-m2m-token) oauth2_get_m2m_token "${args[@]+"${args[@]}"}" ;;
        get-3lo-token) oauth2_get_3lo_token "${args[@]+"${args[@]}"}" ;;
        *)             echo "ERROR: Unknown oauth2 action '$action'" >&2; exit 1 ;;
      esac
      ;;
    delegated)
      [ -z "$REDACT_FIELDS" ] && REDACT_FIELDS="apikey"
      case "$action" in
        list)          delegated_list "${args[@]+"${args[@]}"}" ;;
        create)        delegated_create "${args[@]+"${args[@]}"}" ;;
        get)           delegated_get "${args[@]+"${args[@]}"}" ;;
        delete)        delegated_delete "${args[@]+"${args[@]}"}" ;;
        get-key)       delegated_get_key "${args[@]+"${args[@]}"}" ;;
        *)             echo "ERROR: Unknown delegated action '$action'" >&2; exit 1 ;;
      esac
      ;;
    *)
      echo "ERROR: Unknown provider type '$provider_type'. Use: apikey, oauth2, delegated" >&2
      exit 1
      ;;
  esac
}

main "$@"
