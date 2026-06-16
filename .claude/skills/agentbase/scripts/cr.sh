#!/usr/bin/env bash
# GreenNode AgentBase — Container Registry (CR) Management
# Managed registry: each user has one pre-provisioned repo + one credential pair.
# Usage: bash .claude/skills/agentbase/scripts/cr.sh <resource> <action> [options]

SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPTS_DIR/lib/config.sh"
source "$SCRIPTS_DIR/lib/common.sh"

BASE_URL="$AGENTBASE_CR_URL"

# --- Parse resource + action + common flags ---
RESOURCE="${1:-help}"; shift 2>/dev/null || true
ACTION="${1:-}"; shift 2>/dev/null || true
ARGS=()
while IFS= read -r line; do ARGS+=("$line"); done < <(parse_flags "$@")
if [ ${#ARGS[@]} -gt 0 ]; then set -- "${ARGS[@]}"; else set --; fi

# ===========================
# Repository (single pre-provisioned repo)
# ===========================

repo_get() {
  if [ $# -gt 0 ]; then
    echo "ERROR: repo get takes no arguments (the repo is auto-provisioned)" >&2
    return 1
  fi
  api_call GET "${BASE_URL}/repository"
}

# ===========================
# Credentials (registry username + secret)
# ===========================

credentials_get() {
  if [ $# -gt 0 ]; then
    echo "ERROR: credentials get takes no arguments" >&2
    return 1
  fi
  REDACT_FIELDS="${REDACT_FIELDS:-secret}" api_call GET "${BASE_URL}/registry-credential"
}

credentials_reset() {
  if [ $# -gt 0 ]; then
    echo "ERROR: credentials reset takes no arguments" >&2
    return 1
  fi
  REDACT_FIELDS="${REDACT_FIELDS:-secret}" api_call PATCH "${BASE_URL}/registry-credential/secret"
}

# Convenience: fetch repo + credentials and run `docker login` in one step.
# Secret stays in memory — never written to disk (NO_PERSIST=1 suppresses
# both SAVE_AS and the .agentbase/last_response.json pointer).
credentials_docker_login() {
  local reset=false

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --reset) reset=true; shift ;;
      *) echo "ERROR: Unknown option for credentials docker-login: $1" >&2; return 1 ;;
    esac
  done

  # fd-swap pattern: api_call writes the body to fd 3, which $(...) captures.
  # Anything api_call would print to fd 1 (verbose, dry-run echoes) goes to /dev/null
  # so the JSON never reaches the LLM-visible tool output.
  local repo_json registry_url
  repo_json=$(NO_PERSIST=1 REDACT_FIELDS="" api_call GET "${BASE_URL}/repository" 3>&1 >/dev/null) || return 1
  registry_url=$(echo "$repo_json" | jq -r '.registryUrl // empty')

  if [ -z "$registry_url" ]; then
    echo "ERROR: Could not read registryUrl from repository response" >&2
    return 1
  fi

  local cred_method="GET"
  local cred_path="/registry-credential"
  if [ "$reset" = true ]; then
    cred_method="PATCH"
    cred_path="/registry-credential/secret"
  fi

  local cred_json username secret
  cred_json=$(NO_PERSIST=1 REDACT_FIELDS="" api_call "$cred_method" "${BASE_URL}${cred_path}" 3>&1 >/dev/null) || return 1
  username=$(echo "$cred_json" | jq -r '.username // empty')
  secret=$(echo "$cred_json" | jq -r '.secret // empty')

  if [ -z "$username" ] || [ -z "$secret" ]; then
    echo "ERROR: Could not read username/secret from credentials response" >&2
    return 1
  fi

  # Pipe secret straight into `docker login --password-stdin`. Never echoed.
  echo "$secret" | bash "$SCRIPTS_DIR/docker_login.sh" \
    --registry "$registry_url" \
    --username "$username" \
    --password-stdin
}

# ===========================
# Images
# ===========================

images_list() {
  local name="" page="$DEFAULT_FIRST_PAGE" size="$DEFAULT_PAGE_SIZE"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name) name="$2"; shift 2 ;;
      --page) page="$2"; shift 2 ;;
      --size) size="$2"; shift 2 ;;
      *) echo "ERROR: Unknown option for images list: $1" >&2; return 1 ;;
    esac
  done

  local query
  query=$(build_query "imageName=$name" "page=$page" "size=$size")
  api_call GET "${BASE_URL}/repository/images${query}"
}

images_delete() {
  local name=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name) name="$2"; shift 2 ;;
      *) echo "ERROR: Unknown option for images delete: $1" >&2; return 1 ;;
    esac
  done

  if [ -z "$name" ]; then
    echo "ERROR: --name <imageName> is required for images delete" >&2
    return 1
  fi

  local query
  query=$(build_query "imageName=$name")
  api_call DELETE "${BASE_URL}/repository/images${query}"
}

# ===========================
# Artifacts
# ===========================

artifacts_list() {
  local image="" digest="" page="$DEFAULT_FIRST_PAGE" size="$DEFAULT_PAGE_SIZE"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --image) image="$2"; shift 2 ;;
      --digest) digest="$2"; shift 2 ;;
      --page) page="$2"; shift 2 ;;
      --size) size="$2"; shift 2 ;;
      *) echo "ERROR: Unknown option for artifacts list: $1" >&2; return 1 ;;
    esac
  done

  if [ -z "$image" ]; then
    echo "ERROR: --image <imageName> is required for artifacts list" >&2
    return 1
  fi

  local query
  query=$(build_query "imageName=$image" "digest=$digest" "page=$page" "size=$size")
  api_call GET "${BASE_URL}/repository/artifacts${query}"
}

artifacts_delete() {
  local image="" digest=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --image) image="$2"; shift 2 ;;
      --digest) digest="$2"; shift 2 ;;
      *) echo "ERROR: Unknown option for artifacts delete: $1" >&2; return 1 ;;
    esac
  done

  if [ -z "$image" ] || [ -z "$digest" ]; then
    echo "ERROR: --image <imageName> and --digest <digest> are required for artifacts delete" >&2
    return 1
  fi

  local query
  query=$(build_query "imageName=$image" "digest=$digest")
  api_call DELETE "${BASE_URL}/repository/artifacts${query}"
}

# ===========================
# Help
# ===========================

do_help() {
  show_help ".claude/skills/agentbase/scripts/cr.sh" \
    "Manage GreenNode AgentBase Container Registry (CR).

Every user has one pre-provisioned repo and one credential pair on the
managed registry. Push image URL format: \${registryUrl}/\${repoName}/<image>:<tag>." \
    "  repo get                                                          Get repo info (name, registryUrl, quota, imageCount)

  credentials get                                                   Get username + secret (secret redacted by default)
  credentials reset                                                 Reset (rotate) the secret; returns new credentials
  credentials docker-login [--reset]                                Fetch repo + credentials and run \`docker login\` in one step.
                                                                    Secret is piped via --password-stdin and never written to disk.

  images list      [--name NAME] [--page N] [--size N]              List images in the repo (paginated)
  images delete    --name NAME                                      Delete an image (all artifacts under it)

  artifacts list   --image NAME [--digest DIGEST] [--page N] [--size N]
                                                                    List artifacts of an image (paginated)
  artifacts delete --image NAME --digest DIGEST                     Delete an artifact by digest

  help                                                              Show this help message"
}

# ===========================
# Dispatch
# ===========================

case "$RESOURCE" in
  repo)
    case "$ACTION" in
      get)    repo_get "$@" ;;
      help|"") do_help ;;
      *)      echo "ERROR: Unknown repo action '$ACTION'. Run with 'help' for usage." >&2; exit 1 ;;
    esac
    ;;
  credentials)
    case "$ACTION" in
      get)          credentials_get "$@" ;;
      reset)        credentials_reset "$@" ;;
      docker-login) credentials_docker_login "$@" ;;
      help|"") do_help ;;
      *)      echo "ERROR: Unknown credentials action '$ACTION'. Run with 'help' for usage." >&2; exit 1 ;;
    esac
    ;;
  images)
    case "$ACTION" in
      list)   images_list "$@" ;;
      delete) images_delete "$@" ;;
      help|"") do_help ;;
      *)      echo "ERROR: Unknown images action '$ACTION'. Run with 'help' for usage." >&2; exit 1 ;;
    esac
    ;;
  artifacts)
    case "$ACTION" in
      list)   artifacts_list "$@" ;;
      delete) artifacts_delete "$@" ;;
      help|"") do_help ;;
      *)      echo "ERROR: Unknown artifacts action '$ACTION'. Run with 'help' for usage." >&2; exit 1 ;;
    esac
    ;;
  help|"") do_help ;;
  *)       echo "ERROR: Unknown resource '$RESOURCE'. Run with 'help' for usage." >&2; exit 1 ;;
esac
