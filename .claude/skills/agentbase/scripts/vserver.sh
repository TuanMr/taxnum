#!/usr/bin/env bash
# GreenNode AgentBase — vServer (VPC / subnet discovery)
# Used to look up vpcId / subnetId required by Custom Agent VPC mode.
# Usage: bash .claude/skills/agentbase/scripts/vserver.sh <action> [options]
#
# Flow:
#   1. projects                    -> get project IDs (usually one per user)
#   2. vpcs <project>              -> list VPCs in a project
#   3. subnets <project> <vpc>     -> list subnets of a VPC
#   4. validate-vpc <project> <vpc>  -> check vDNS enabled + CIDR doesn't overlap system

SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPTS_DIR/lib/config.sh"
source "$SCRIPTS_DIR/lib/common.sh"

BASE_URL="$VSERVER_URL"

# --- Parse action + common flags ---
ACTION="${1:-help}"; shift 2>/dev/null || true
ARGS=()
while IFS= read -r line; do ARGS+=("$line"); done < <(parse_flags "$@")
if [ ${#ARGS[@]} -gt 0 ]; then set -- "${ARGS[@]}"; else set --; fi

# --- Filter helpers — keep only fields useful for picking IDs ---

filter_vpc() {
  jq '{
    id,
    name: .displayName,
    cidr,
    status,
    dnsStatus,
    dnsId,
    routeTableId,
    zone: (.zone.displayName // .zone.name // null),
    createdAt
  }'
}

filter_subnet() {
  jq '{
    id: .uuid,
    name,
    cidr,
    status,
    networkUuid,
    zone: (.zone.displayName // .zone.name // null),
    createdAt
  }'
}

# ===========================
# Actions
# ===========================

do_projects() {
  if [ $# -gt 0 ]; then
    echo "ERROR: projects takes no arguments" >&2; return 1
  fi
  api_call GET "$BASE_URL/v1/projects" \
    | jq '{projects: (.projects // [] | map({projectId, userId}))}'
}

do_vpcs() {
  local project_id="${1:-}"; shift 2>/dev/null || true
  if [ -z "$project_id" ]; then
    echo "ERROR: usage: vpcs <project_id> [--page N] [--size N] [--name <substr>]" >&2
    return 1
  fi
  local page="$DEFAULT_FIRST_PAGE" size="$DEFAULT_PAGE_SIZE" name=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --page) page="$2"; shift 2 ;;
      --size) size="$2"; shift 2 ;;
      --name) name="$2"; shift 2 ;;
      *) echo "ERROR: Unknown option: $1" >&2; return 1 ;;
    esac
  done
  local query
  query=$(build_query "page=$page" "pageSize=$size" "name=$name")
  api_call GET "$BASE_URL/v2/$project_id/networks$query" \
    | jq '{
        page, pageSize, totalItem, totalPage,
        listData: (.listData // [] | map({
          id, name: .displayName, cidr, status, dnsStatus, dnsId,
          zone: (.zone.displayName // .zone.name // null)
        }))
      }'
}

do_vpc() {
  local project_id="${1:-}" vpc_id="${2:-}"
  if [ -z "$project_id" ] || [ -z "$vpc_id" ]; then
    echo "ERROR: usage: vpc <project_id> <vpc_id>" >&2
    return 1
  fi
  api_call GET "$BASE_URL/v2/$project_id/networks/$vpc_id" | filter_vpc
}

do_subnets() {
  local project_id="${1:-}" vpc_id="${2:-}"
  if [ -z "$project_id" ] || [ -z "$vpc_id" ]; then
    echo "ERROR: usage: subnets <project_id> <vpc_id>" >&2
    return 1
  fi
  # Endpoint returns a flat array (not paginated).
  api_call GET "$BASE_URL/v2/$project_id/networks/$vpc_id/subnets" \
    | jq 'map({
        id: .uuid, name, cidr, status, networkUuid,
        zone: (.zone.displayName // .zone.name // null)
      })'
}

do_subnet() {
  local project_id="${1:-}" vpc_id="${2:-}" subnet_id="${3:-}"
  if [ -z "$project_id" ] || [ -z "$vpc_id" ] || [ -z "$subnet_id" ]; then
    echo "ERROR: usage: subnet <project_id> <vpc_id> <subnet_id>" >&2
    return 1
  fi
  api_call GET "$BASE_URL/v2/$project_id/networks/$vpc_id/subnets/$subnet_id" | filter_subnet
}

# --- Validate a VPC for Custom Agent VPC mode ---
#   1. vDNS must be enabled on the VPC.
#   2. VPC CIDR MUST NOT overlap with the system CIDR (default 172.30.0.0/16).
do_validate_vpc() {
  local project_id="${1:-}" vpc_id="${2:-}"
  if [ -z "$project_id" ] || [ -z "$vpc_id" ]; then
    echo "ERROR: usage: validate-vpc <project_id> <vpc_id> [--system-cidr CIDR]" >&2
    return 1
  fi
  shift 2
  local system_cidr="$AGENTBASE_SYSTEM_CIDR"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --system-cidr) system_cidr="$2"; shift 2 ;;
      *) echo "ERROR: Unknown option: $1" >&2; return 1 ;;
    esac
  done

  local vpc_json
  vpc_json=$(api_call GET "$BASE_URL/v2/$project_id/networks/$vpc_id" 2>/dev/null) || return 1
  local cidr dns_status dns_id name
  cidr=$(echo "$vpc_json" | jq -r '.cidr // ""')
  dns_status=$(echo "$vpc_json" | jq -r '.dnsStatus // ""')
  dns_id=$(echo "$vpc_json" | jq -r '.dnsId // ""')
  name=$(echo "$vpc_json" | jq -r '.displayName // .id // ""')

  # --- Check 1: vDNS enabled ---
  # Treat as enabled when dnsStatus matches ACTIVE/ENABLED/ON, or when a non-empty dnsId is present.
  local dns_ok="false"
  case "$(echo "$dns_status" | tr '[:lower:]' '[:upper:]')" in
    ACTIVE|ENABLED|ON|CREATED|AVAILABLE) dns_ok="true" ;;
  esac
  if [ "$dns_ok" != "true" ] && [ -n "$dns_id" ]; then
    dns_ok="true"
  fi

  # --- Check 2: CIDR overlap with system CIDR ---
  local overlap_result
  overlap_result=$(python3 - "$cidr" "$system_cidr" <<'PY'
import ipaddress, sys
try:
    a = ipaddress.ip_network(sys.argv[1], strict=False)
    b = ipaddress.ip_network(sys.argv[2], strict=False)
except ValueError as e:
    print(f"invalid:{e}")
    sys.exit(0)
print("overlap" if a.overlaps(b) else "ok")
PY
) || overlap_result="unknown"

  # --- Emit a single JSON report ---
  local cidr_ok="false"
  case "$overlap_result" in
    ok) cidr_ok="true" ;;
  esac

  local overall="true"
  if [ "$dns_ok" != "true" ] || [ "$cidr_ok" != "true" ]; then
    overall="false"
  fi

  jq -n \
    --arg vpcId "$vpc_id" \
    --arg name "$name" \
    --arg cidr "$cidr" \
    --arg systemCidr "$system_cidr" \
    --arg dnsStatus "$dns_status" \
    --arg dnsId "$dns_id" \
    --argjson dnsEnabled "$dns_ok" \
    --argjson cidrOk "$cidr_ok" \
    --arg overlapResult "$overlap_result" \
    --argjson ok "$overall" \
    '{
      ok: $ok,
      vpcId: $vpcId, name: $name, cidr: $cidr,
      systemCidr: $systemCidr,
      checks: {
        vdnsEnabled: { ok: $dnsEnabled, dnsStatus: $dnsStatus, dnsId: $dnsId },
        cidrNoOverlap: { ok: $cidrOk, result: $overlapResult }
      }
    }'

  if [ "$overall" = "true" ]; then return 0; else return 1; fi
}

# ===========================
# Dispatch
# ===========================

case "$ACTION" in
  projects)      do_projects "$@" ;;
  vpcs)          do_vpcs "$@" ;;
  vpc)           do_vpc "$@" ;;
  subnets)       do_subnets "$@" ;;
  subnet)        do_subnet "$@" ;;
  validate-vpc)  do_validate_vpc "$@" ;;
  help|-h|--help|"")
    cat <<EOF
Usage: bash $(basename "$0") <action> [options]

Discover VPC / subnet IDs from the vServer API. Required when creating a
Custom Agent runtime in VPC mode (--network-mode VPC).

Actions:
  projects                                  List projects for the caller.
  vpcs <project> [--page N --size N --name X]
                                            List VPCs in a project (filtered).
  vpc <project> <vpc>                       Get a single VPC (filtered).
  subnets <project> <vpc>                   List subnets of a VPC (filtered).
  subnet <project> <vpc> <subnet>           Get a single subnet (filtered).
  validate-vpc <project> <vpc> [--system-cidr CIDR]
                                            Check VPC has vDNS enabled and its
                                            CIDR does not overlap the system CIDR
                                            (default: \$AGENTBASE_SYSTEM_CIDR =
                                            $AGENTBASE_SYSTEM_CIDR).

Configuration:
  GREENNODE_REGION        hcm (default) | han — picks vServer region endpoint.
  AGENTBASE_SYSTEM_CIDR   Override the system CIDR used by validate-vpc.

Common flags (parsed by lib/common.sh):
  --verbose, -v   Show request/response details.
  --dry-run       Print the curl command without executing.

Examples:
  bash $(basename "$0") projects
  bash $(basename "$0") vpcs proj-xxxxxxxx
  bash $(basename "$0") subnets proj-xxxxxxxx net-yyyyyyyy
  bash $(basename "$0") validate-vpc proj-xxxxxxxx net-yyyyyyyy
EOF
    ;;
  *)
    echo "ERROR: Unknown action: $ACTION (run with --help)" >&2
    exit 1
    ;;
esac
