#!/usr/bin/env bash
# GreenNode AgentBase — Resource Discovery across all services
# Usage: bash .claude/skills/agentbase/scripts/discovery.sh [action] [options]

SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPTS_DIR/lib/config.sh"
source "$SCRIPTS_DIR/lib/common.sh"

# --- Parse action + common flags ---
ACTION="${1:-all}"; shift 2>/dev/null || true
ARGS=()
while IFS= read -r line; do ARGS+=("$line"); done < <(parse_flags "$@")
if [ ${#ARGS[@]} -gt 0 ]; then set -- "${ARGS[@]}"; else set --; fi

DISCOVERY_FILE="$AGENTBASE_DIR/discovery.json"

# --- Fetch a single resource type ---
# fetch_resource LABEL URL ITEMS_PATH TMPDIR
# Writes JSON result to TMPDIR/<label>.json
fetch_resource() {
  local label="$1"
  local url="$2"
  local items_path="$3"
  local tmpdir="$4"
  local outfile="$tmpdir/${label}.json"

  if [ "$DRY_RUN" = true ]; then
    echo "[dry-run] Would fetch $label: GET $url" >&2
    echo '{"items":[],"count":0,"error":null}' > "$outfile"
    return 0
  fi

  local response
  if response=$(api_call GET "$url" 2>/dev/null); then
    local items count
    items=$(echo "$response" | jq -c "$items_path // []" 2>/dev/null || echo '[]')
    count=$(echo "$items" | jq 'length' 2>/dev/null || echo '0')
    jq -n --argjson items "$items" --argjson count "$count" \
      '{items: $items, count: $count, error: null}' > "$outfile"
  else
    jq -n --arg err "Could not fetch $label" \
      '{items: [], count: 0, error: $err}' > "$outfile"
  fi
}

# --- Format helpers ---

print_section() {
  local label="$1"
  local file="$2"
  local formatter="$3"

  local error count
  error=$(jq -r '.error // empty' "$file" 2>/dev/null)
  count=$(jq -r '.count' "$file" 2>/dev/null || echo 0)

  echo ""
  if [ -n "$error" ]; then
    echo "=== $label (error) ==="
    echo "  $error"
    return
  fi

  echo "=== $label ($count) ==="
  if [ "$count" -eq 0 ]; then
    echo "  (none)"
  else
    jq -r ".items[] | $formatter" "$file" 2>/dev/null | sed 's/^/  /'
  fi
}

# --- Main discovery ---

do_all() {
  init_token

  local tmpdir
  tmpdir=$(mktemp -d /tmp/agentbase.XXXXXX)
  trap "rm -rf '$tmpdir'" EXIT

  if [ "$VERBOSE" = true ]; then
    echo ">>> Fetching all resources in parallel..." >&2
  fi

  # Launch all fetches in parallel
  fetch_resource "agent_identities" \
    "${AGENTBASE_IDENTITY_URL}/agent-identities?page=${IDENTITY_FIRST_PAGE}&size=${DEFAULT_PAGE_SIZE}" \
    ".content" "$tmpdir" &

  fetch_resource "api_key_providers" \
    "${AGENTBASE_IDENTITY_URL}/outbound-auth/api-key-providers?page=${IDENTITY_FIRST_PAGE}&size=${DEFAULT_PAGE_SIZE}" \
    ".content" "$tmpdir" &

  fetch_resource "delegated_api_key_providers" \
    "${AGENTBASE_IDENTITY_URL}/outbound-auth/delegated-api-key-providers?page=${IDENTITY_FIRST_PAGE}&size=${DEFAULT_PAGE_SIZE}" \
    ".content" "$tmpdir" &

  fetch_resource "oauth2_providers" \
    "${AGENTBASE_IDENTITY_URL}/outbound-auth/oauth2-providers?page=${IDENTITY_FIRST_PAGE}&size=${DEFAULT_PAGE_SIZE}" \
    ".content" "$tmpdir" &

  fetch_resource "runtimes" \
    "${AGENTBASE_RUNTIME_URL}/agent-runtimes?page=${DEFAULT_FIRST_PAGE}&size=${DEFAULT_PAGE_SIZE}" \
    ".listData" "$tmpdir" &

  fetch_resource "memories" \
    "${AGENTBASE_MEMORY_URL}/memories?page=${DEFAULT_FIRST_PAGE}&size=${DEFAULT_PAGE_SIZE}" \
    ".listData" "$tmpdir" &

  fetch_resource "aip_api_keys" \
    "${AIP_MANAGEMENT_URL}/v1/api-keys?page=${DEFAULT_FIRST_PAGE}&size=${DEFAULT_PAGE_SIZE}" \
    ".listData" "$tmpdir" &

  fetch_resource "cr_repository" \
    "${AGENTBASE_CR_URL}/repository" \
    "[.]" "$tmpdir" &

  wait

  # Save combined JSON
  mkdir -p "$AGENTBASE_DIR"
  jq -n \
    --slurpfile agent_identities "$tmpdir/agent_identities.json" \
    --slurpfile api_key_providers "$tmpdir/api_key_providers.json" \
    --slurpfile delegated_api_key_providers "$tmpdir/delegated_api_key_providers.json" \
    --slurpfile oauth2_providers "$tmpdir/oauth2_providers.json" \
    --slurpfile runtimes "$tmpdir/runtimes.json" \
    --slurpfile memories "$tmpdir/memories.json" \
    --slurpfile aip_api_keys "$tmpdir/aip_api_keys.json" \
    --slurpfile cr_repository "$tmpdir/cr_repository.json" \
    '{
      agentIdentities: $agent_identities[0],
      apiKeyProviders: $api_key_providers[0],
      delegatedApiKeyProviders: $delegated_api_key_providers[0],
      oauth2Providers: $oauth2_providers[0],
      runtimes: $runtimes[0],
      memories: $memories[0],
      aipApiKeys: $aip_api_keys[0],
      crRepository: $cr_repository[0]
    }' > "$DISCOVERY_FILE"

  if [ "$VERBOSE" = true ]; then
    echo ">>> Saved full results to $DISCOVERY_FILE" >&2
  fi

  # Print summary
  echo "GreenNode AgentBase — Resource Discovery"
  echo "========================================="

  print_section "Agent Identities" "$tmpdir/agent_identities.json" \
    '"\(.name // .id // "unknown")\t\(.createdAt // .created_at // "-" | split("T")[0] // "-")"'

  print_section "API Key Providers" "$tmpdir/api_key_providers.json" \
    '"\(.name // .id // "unknown")\t\(.createdAt // .created_at // "-" | split("T")[0] // "-")"'

  print_section "Delegated API Key Providers" "$tmpdir/delegated_api_key_providers.json" \
    '"\(.name // .id // "unknown")\t\(.createdAt // .created_at // "-" | split("T")[0] // "-")"'

  print_section "OAuth2 Providers" "$tmpdir/oauth2_providers.json" \
    '"\(.name // .id // "unknown")\t\(.createdAt // .created_at // "-" | split("T")[0] // "-")"'

  print_section "Runtimes" "$tmpdir/runtimes.json" \
    '"\(.id // "unknown")\t\(.name // "-")\t\(.status // "-")\t\(.createdAt // .created_at // "-" | split("T")[0] // "-")"'

  print_section "Memories" "$tmpdir/memories.json" \
    '"\(.id // "unknown")\t\(.name // "-")\t\(.status // "-")\t\(.createdAt // .created_at // "-" | split("T")[0] // "-")"'

  print_section "AIP API Keys" "$tmpdir/aip_api_keys.json" \
    '"\(.id // "unknown")\t\(.name // "-")\t\(.status // "-")\t\(.createdAt // .created_at // "-" | split("T")[0] // "-")"'

  print_section "Container Registry" "$tmpdir/cr_repository.json" \
    '"\(.name // "-")\tregistry=\(.registryUrl // "-")\timages=\(.imageCount // 0)\tquota=\(.quotaUsed // 0)/\(.quotaLimit // 0)"'

  echo ""
  echo "Full JSON saved to: $DISCOVERY_FILE"
}

do_json() {
  init_token

  local tmpdir
  tmpdir=$(mktemp -d /tmp/agentbase.XXXXXX)
  trap "rm -rf '$tmpdir'" EXIT

  if [ "$VERBOSE" = true ]; then
    echo ">>> Fetching all resources in parallel..." >&2
  fi

  fetch_resource "agent_identities" \
    "${AGENTBASE_IDENTITY_URL}/agent-identities?page=${IDENTITY_FIRST_PAGE}&size=${DEFAULT_PAGE_SIZE}" \
    ".content" "$tmpdir" &

  fetch_resource "api_key_providers" \
    "${AGENTBASE_IDENTITY_URL}/outbound-auth/api-key-providers?page=${IDENTITY_FIRST_PAGE}&size=${DEFAULT_PAGE_SIZE}" \
    ".content" "$tmpdir" &

  fetch_resource "delegated_api_key_providers" \
    "${AGENTBASE_IDENTITY_URL}/outbound-auth/delegated-api-key-providers?page=${IDENTITY_FIRST_PAGE}&size=${DEFAULT_PAGE_SIZE}" \
    ".content" "$tmpdir" &

  fetch_resource "oauth2_providers" \
    "${AGENTBASE_IDENTITY_URL}/outbound-auth/oauth2-providers?page=${IDENTITY_FIRST_PAGE}&size=${DEFAULT_PAGE_SIZE}" \
    ".content" "$tmpdir" &

  fetch_resource "runtimes" \
    "${AGENTBASE_RUNTIME_URL}/agent-runtimes?page=${DEFAULT_FIRST_PAGE}&size=${DEFAULT_PAGE_SIZE}" \
    ".listData" "$tmpdir" &

  fetch_resource "memories" \
    "${AGENTBASE_MEMORY_URL}/memories?page=${DEFAULT_FIRST_PAGE}&size=${DEFAULT_PAGE_SIZE}" \
    ".listData" "$tmpdir" &

  fetch_resource "aip_api_keys" \
    "${AIP_MANAGEMENT_URL}/v1/api-keys?page=${DEFAULT_FIRST_PAGE}&size=${DEFAULT_PAGE_SIZE}" \
    ".listData" "$tmpdir" &

  fetch_resource "cr_repository" \
    "${AGENTBASE_CR_URL}/repository" \
    "[.]" "$tmpdir" &

  wait

  # Build and output combined JSON
  mkdir -p "$AGENTBASE_DIR"
  jq -n \
    --slurpfile agent_identities "$tmpdir/agent_identities.json" \
    --slurpfile api_key_providers "$tmpdir/api_key_providers.json" \
    --slurpfile delegated_api_key_providers "$tmpdir/delegated_api_key_providers.json" \
    --slurpfile oauth2_providers "$tmpdir/oauth2_providers.json" \
    --slurpfile runtimes "$tmpdir/runtimes.json" \
    --slurpfile memories "$tmpdir/memories.json" \
    --slurpfile aip_api_keys "$tmpdir/aip_api_keys.json" \
    --slurpfile cr_repository "$tmpdir/cr_repository.json" \
    '{
      agentIdentities: $agent_identities[0],
      apiKeyProviders: $api_key_providers[0],
      delegatedApiKeyProviders: $delegated_api_key_providers[0],
      oauth2Providers: $oauth2_providers[0],
      runtimes: $runtimes[0],
      memories: $memories[0],
      aipApiKeys: $aip_api_keys[0],
      crRepository: $cr_repository[0]
    }' | tee "$DISCOVERY_FILE"
}

do_help() {
  show_help ".claude/skills/agentbase/scripts/discovery.sh" \
    "Discover all GreenNode AgentBase resources across services." \
    "  all    Fetch all resources and display summary (default)
  json   Output raw JSON (all resources combined)
  help   Show this help message"
}

# --- Dispatch ---
case "$ACTION" in
  all)  do_all "$@" ;;
  json) do_json "$@" ;;
  help) do_help ;;
  *)    echo "ERROR: Unknown action '$ACTION'. Run with 'help' for usage." >&2; exit 1 ;;
esac
