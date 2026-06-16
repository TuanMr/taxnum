#!/usr/bin/env bash
# GreenNode AgentBase API Configuration
# Source this file to get base URLs and constants.
# Usage: source "$(dirname "$0")/lib/config.sh"

# --- Base URLs ---
export AGENTBASE_IDENTITY_URL="https://agentbase.api.vngcloud.vn/identity/api/v1"
export AGENTBASE_RUNTIME_URL="https://agentbase.api.vngcloud.vn/runtime"
export AGENTBASE_MEMORY_URL="https://agentbase.api.vngcloud.vn/memory"
export AGENTBASE_CR_URL="https://agentbase.api.vngcloud.vn/cr/api/v1"
export AIP_MANAGEMENT_URL="https://aiplatform-hcm.api.vngcloud.vn"
export AIP_LLM_URL="https://maas-llm-aiplatform-hcm.api.vngcloud.vn/v1"
export IAM_TOKEN_URL="https://iam.api.vngcloud.vn/accounts-api/v2/auth/token"

# --- vServer (VPC / subnet discovery for Custom Agent VPC mode) ---
# Default region = HCM-3. Override with GREENNODE_REGION=han to use HAN-1.
if [ "${GREENNODE_REGION:-hcm}" = "han" ]; then
  export VSERVER_URL="https://han-1.api.vngcloud.vn/vserver/vserver-gateway"
else
  export VSERVER_URL="https://hcm-3.api.vngcloud.vn/vserver/vserver-gateway"
fi

# System CIDR that user VPCs MUST NOT overlap with when running Custom Agents
# in VPC mode. Will move to the platform docs eventually; hard-coded for now.
export AGENTBASE_SYSTEM_CIDR="${AGENTBASE_SYSTEM_CIDR:-172.30.0.0/16}"

# --- Pagination defaults ---
# Identity service is 0-indexed; Runtime/Memory/vCR/AIP are 1-indexed
export IDENTITY_FIRST_PAGE=0
export DEFAULT_FIRST_PAGE=1
export DEFAULT_PAGE_SIZE=100

# --- Response field names ---
# Identity uses Spring-style: content, totalElements, totalPages
# Others use GreenNode-style: listData, totalItem, totalPage
