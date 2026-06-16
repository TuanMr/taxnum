---
name: agentbase
description: "Platform reference and getting-started guide. Use for general questions about the platform, architecture, available services, SDK, IAM setup, credentials, or which skill to use. IMPORTANT - If the user wants to BUILD an agent (not just learn about the platform), use /agentbase-wizard instead — do not answer with reference material. Trigger phrases include how does the platform work, what services are available, platform overview, explain the architecture, which skill should I use, how do I get started, what can I do here, how do I set up credentials, IAM setup. This is a reference guide — for specific operations, invoke the dedicated skill."
---

# GreenNode AgentBase Platform Reference

## Getting Started

New to GreenNode AgentBase? Use `/agentbase-wizard` for step-by-step guidance from zero to deployed agent.

## Overview

AgentBase is a dedicated infrastructure platform for enterprise AI agents by GreenNode. It provides identity management, containerized runtime, memory services, and observability.

## Platform Components

### 1. Identity Service
- **Base URL**: `https://agentbase.api.vngcloud.vn/identity/api/v1`
- **Console**: https://aiplatform.console.vngcloud.vn/access-control
- Manages agent identities and outbound authentication (API Keys, Delegated Keys, OAuth2)

### 2. Runtime Service
- **Base URL**: `https://agentbase.api.vngcloud.vn/runtime`
- **Console**: https://aiplatform.console.vngcloud.vn/agent-runtime?tab=runtime
- Hosts two resource types:
  - **Custom Agent** (`/agent-runtimes`) — user-built Docker images. Supports autoscaling, named endpoints (canary + DEFAULT), versioning, zero-downtime deploys, and optional VPC network mode (`networkConfig` with `mode`, `vpcId`, `subnetId`, `routeCidrs`). Default trigger for wizard-built agents.
  - **OpenClaw** (`/openclaws`) — pre-built template agents (Telegram / Zalo chat bots) parameterized by version, flavor, model provider, and channel tokens. No Docker image required.

  See `/agentbase-deploy` for both flows.

  **VPC mode discovery** — Custom Agent VPC mode requires `vpcId` and `subnetId` from VNG Cloud's vServer service (`https://hcm-3.api.vngcloud.vn/vserver/vserver-gateway`, or `han-1.*` for HAN). Use `bash .claude/skills/agentbase/scripts/vserver.sh projects | vpcs | subnets | validate-vpc` to look them up and check vDNS + CIDR-overlap pre-flight before calling `runtime.sh create`. The default forbidden system CIDR is `172.30.0.0/16` (`AGENTBASE_SYSTEM_CIDR`).

### 3. Memory Service
- **Base URL**: `https://agentbase.api.vngcloud.vn/memory`
- **Console**: https://aiplatform.console.vngcloud.vn/memory
- Conversation history (short-term) and semantic fact extraction (long-term memory)

### 4. Observability
- Accessed via Runtime Service API
- Runtime and endpoint logs, CPU/RAM metrics
- See `/agentbase-monitor` skill for log viewing and debugging

## Authentication (All Services)

All AgentBase API calls require a GreenNode IAM bearer token, obtained from an IAM Service Account.

> **Runtime vs Local Development**: When an agent is deployed on AgentBase Runtime, the runtime system automatically manages the IAM service account and Agent Identity, and injects them as environment variables (`GREENNODE_CLIENT_ID`, `GREENNODE_CLIENT_SECRET`, `GREENNODE_AGENT_IDENTITY`) into the container. The SDK automatically uses these — no manual credential configuration needed in agent code. The manual setup below is only needed for **local development** and for **calling platform management APIs** (e.g., creating runtimes, managing identities) from outside the runtime environment.

### Step 1: Create IAM Service Account

1. Go to **IAM Console**: https://iam.console.vngcloud.vn/service-accounts
2. Click **"Create service account"**
3. Fill in a descriptive **Name** (e.g., `agentbase-dev`)
4. Attach permissions (see Step 2)
5. Click create — **immediately copy the Client Secret** (shown only once, cannot be retrieved later; can only be reset)

### Step 2: Grant Permissions for AgentBase

On the Service Account detail page, go to the **"Permission"** tab and click **"Attach Policies"**.

To ensure smooth usage without permission issues, search for and attach these policies:
- `AgentBaseFullAccess`
- `vcrFullAccess`
- `AiPlatformFullAccess`

> If no AgentBase-specific policy appears, you can create a custom policy at https://iam.console.vngcloud.vn/policies — select the desired actions, then attach the policy to your service account.

### Step 3: Get client_id and client_secret

1. Go to https://iam.console.vngcloud.vn/service-accounts
2. Click your service account to open its detail page
3. Go to **"Security credentials"** tab
4. **Client ID**: always visible — copy it directly
5. **Client Secret**: only shown at creation time. If lost, click **"Reset"** to generate a new one (old secret is invalidated immediately)

Store credentials using one of the methods below. The SDK checks them in this priority order:

1. **Environment variables** (highest priority):

**macOS/Linux:**
```bash
export GREENNODE_CLIENT_ID="<your-client-id>"
export GREENNODE_CLIENT_SECRET="<your-client-secret>"
```

**Windows (PowerShell):**
```powershell
$env:GREENNODE_CLIENT_ID = "<your-client-id>"
$env:GREENNODE_CLIENT_SECRET = "<your-client-secret>"
```

2. **`.greennode.json`** in the current working directory (fallback):
```json
{
  "client_id": "<your-client-id>",
  "client_secret": "<your-client-secret>"
}
```

> **Credential storage guide**: IAM credentials (`client_id`, `client_secret`) go in environment variables or `.greennode.json`. LLM configuration (`LLM_API_KEY`, `LLM_BASE_URL`, `LLM_MODEL`) goes in `.env`. These are separate concerns — IAM credentials authenticate with GreenNode platform APIs, while `.env` holds application-level config like LLM provider settings. The agent supports any OpenAI-compatible LLM provider (GreenNode AIP, OpenAI, Ollama, etc.).

### Step 4: Get Bearer Token

Use the token script: `TOKEN=$(bash .claude/skills/agentbase/scripts/get_token.sh)`. It caches the token in `.agentbase/token_cache` and validates expiry via JWT `exp` claim. On 401: re-run with `--force`.

**Never fetch tokens with inline curl — always use the token script.**

Use in API calls: `Authorization: Bearer $TOKEN`

> **Cross-platform note**: The bash/curl commands in this guide work on macOS, Linux, WSL, and Git Bash. On Windows PowerShell, use `$TOKEN` (instead of `TOKEN`), `$env:VAR` (instead of `$VAR`), and backtick `` ` `` (instead of `\`) for line continuation. Use `curl.exe` (not `curl`) in PowerShell, since `curl` is an alias for `Invoke-WebRequest`.

## API Endpoints & Pagination

See the shared reference at `references/endpoints.md` for all API base URLs, pagination conventions, and response shape documentation.

**Important**: Pagination is **not consistent** across services:
- **Identity Service**: `page` is **0-indexed** (first page = `page=0`)
- **Runtime Service**: `page` is **1-indexed** (first page = `page=1`)
- **Memory Service**: `page` is **1-indexed** (first page = `page=1`)

**Important**: Response shapes differ across services:
- **Identity Service** (Spring-style): items in `.content`, count in `.totalElements`, pages in `.totalPages`
- **Runtime / Memory / vCR / AIP** (GreenNode-style): items in `.listData`, count in `.totalItem`, pages in `.totalPage`

See `references/endpoints.md` for full response JSON examples.

## Python SDKs

### greennode-agentbase (Main SDK)
```python
from greennode_agentbase import (
    GreenNodeAgentBaseApp,     # Web server for agent
    RequestContext,            # HTTP request metadata
    PingStatus,                # Health status enum (HEALTHY, HEALTHY_BUSY)
    IdentityClient,            # Identity service client
    MemoryClient,              # Memory service client
    IAMCredentials,            # Auth credentials
    requires_api_key,          # Decorator for static API key injection
    requires_access_token,     # Decorator for OAuth2 token injection
)
from greennode_agentbase.identity import (
    CreateAgentIdentityRequest,
    UpdateAgentIdentityRequest,
    CreateApikeyProviderRequest,
    UpdateApikeyProviderRequest,
    CreateDelegatedApiKeyProviderRequest,
    CreateOauth2ProviderRequest,
    UpdateOauth2ProviderRequest,
    GetDelegatedApiKeyRequest,
    GetM2mTokenRequest,
    ThreeLoTokenRequest,
)
from greennode_agentbase.memory.models import (
    MemoryCreateRequest,
    LongTermMemoryStrategy,
    EventCreateRequest,
    ChatMessage,
    MemoryRecordSearchRequest,
)
# For long-term memory, use MemoryClient in tool-based approach
# (remember/recall tools). See /agentbase-memory for details.
```

**Configuration** (priority: env vars > .greennode.json > defaults):
- `GREENNODE_CLIENT_ID` / `GREENNODE_CLIENT_SECRET` - IAM credentials
- `GREENNODE_AGENT_IDENTITY` - Agent identity name

> On AgentBase Runtime, IAM service account and Agent Identity are managed by the runtime system and automatically available to the SDK — no manual configuration needed.

### greennode-agent-bridge[langgraph] (Framework Bridge)
```python
from greennode_agent_bridge import (
    AgentBaseMemoryEvents,     # LangGraph CheckpointSaver (short-term memory)
)
```

> **Long-term memory**: For long-term memory operations (semantic search, fact storage/retrieval), use tool-based approach with `MemoryClient` SDK (`remember`/`recall` tools). See `/agentbase-memory` for details.

## Runtime Service Contract

See the shared reference at `references/runtime-contract.md` for the full Runtime Service Contract (port, health check, headers, auto-injection).

## Automated IAM Service Account Setup

When any AgentBase skill needs IAM credentials and the user does not have a service account yet, follow this flow:

### Critical Rules

- **This flow is strictly for CREATING a new service account.** Do NOT reset, modify, or delete any existing service account.
- **If a service account with a matching or similar name already exists on the list page**, you MUST stop and inform the user. Present the following options and wait for the user to choose:
  1. **Use the existing one** — ask the user to provide the `client_id` and `client_secret` for the existing service account (or reset it themselves manually)
  2. **Create a new one with a different name** — proceed with the creation flow using a different name
- **NEVER reset an existing service account's credentials** — resetting invalidates the old secret immediately and may break other systems using it. Only the user should decide to reset, and they should do it manually.
- **Always confirm before every significant action (HARD GATE)** — before clicking any button that creates, modifies, or deletes anything, tell the user what you are about to do and wait for their explicit confirmation. Only proceed when the user responds with an explicit confirmation keyword: `yes`, `confirm`, `ok`, `approve`, `proceed`, `go ahead`, `do it`, `lgtm`, or equivalent affirmative. If the user responds with ANYTHING ELSE (parameter changes, questions, corrections, or ambiguous text), treat it as adjustment input — update and re-present for confirmation again. NEVER interpret a non-confirmation response as approval.

### If you have browser automation capability (e.g., MCP browser tool):

1. Open the IAM Console: `https://iam.console.vngcloud.vn/service-accounts`
2. If a login page appears, **do NOT click or interact with any element on the login page** — inform the user they need to log in manually (the user must choose their account type and enter credentials themselves) and wait for them to complete the login before proceeding
3. Once on the service accounts page, **check if a service account with a matching or similar name already exists**. If yes, stop and follow the "Critical Rules" above. If no matching service account exists, proceed.
4. Click **"Create a Service Account"**
5. **Ask the user** for the following before filling in the form. You may recommend defaults, but the user must confirm each value:
   - **Name** — recommend e.g. `agentbase-dev`, but let the user choose
   - **Description** — recommend a brief description, but let the user choose (can be left empty)
6. Fill in the Name and Description as confirmed by the user
7. Click **Next Step**
8. **Ask the user** which permission policies to attach. Recommend the following policies for full AgentBase access, but let the user choose which ones to attach:
   - `AgentBaseFullAccess` — access to AgentBase services (Identity, Runtime, Memory)
   - `vcrFullAccess` — access to GreenNode Container Registry (needed for Docker image push/pull)
   - `AiPlatformFullAccess` — access to AI Platform LLM models and API keys
9. Search for and select the policies the user confirmed
10. **Before clicking Create**, tell the user: "I'm about to create service account '[name]' with policies [list]. Confirm?" — wait for explicit confirmation.
11. Click **Create Service Account**
12. **Immediately capture the Client Secret** from the popup shown on screen (it is only shown once)
13. Click **"Back to list"** to return to the service accounts list page
14. Locate the service account just created (by name) and copy its **Client ID**
15. Set up the credentials using the obtained `client_id` and `client_secret`:
    - Set environment variables `GREENNODE_CLIENT_ID` and `GREENNODE_CLIENT_SECRET`, or
    - Write them to `.greennode.json`
16. If any error occurs during these steps, report the error to the user clearly

### If you do NOT have browser automation capability:

Inform the user that they need to create an IAM Service Account manually, and direct them to the instructions in the **"Authentication (All Services)"** section above (Step 1 through Step 3). Provide the direct link: https://iam.console.vngcloud.vn/service-accounts

## Available Skills
- `/agentbase-wizard` - Guided full lifecycle wizard (start here if new). Also handles project scaffolding (`/agentbase-wizard init`) and testing (`/agentbase-wizard test`)
- `/agentbase-identity` - Manage agent identities and outbound authentication (API keys, OAuth2)
- `/agentbase-memory` - Add memory to agents — conversation history and long-term fact extraction
- `/agentbase-deploy` - Full deploy workflow, runtime management, and managed Container Registry (CR)
- `/agentbase-monitor` - View logs, metrics, status dashboard, and debug running agents
- `/agentbase-teardown` - Clean up and remove all resources for a project
- `/agentbase-llm` - Manage GreenNode AI Platform resources (API keys, models)
