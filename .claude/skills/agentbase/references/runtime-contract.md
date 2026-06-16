# Runtime Service Contract

## Required by the platform (HARD)

Every container deployed on AgentBase Runtime MUST meet these two requirements — they are all the platform enforces:

1. **Port**: Listen on port `8080` — the platform routes all traffic here.
2. **Health check**: Expose `GET /health` returning HTTP 200 when ready — used to mark the runtime `ACTIVE`.

A container that satisfies only these two will deploy and reach `ACTIVE`. How it serves business requests (routes, payload shape) is entirely up to the user.

## SDK convention (NOT enforced by the platform)

If the user builds their agent with the GreenNode AgentBase SDK (`greennode-agentbase`), the SDK exposes the main entrypoint at:

- **`POST /invocations`**

This path is a **convention of the SDK only** — the platform does NOT require it. Users who do not use the SDK are free to handle requests on any path(s) they choose; they just need to satisfy the two hard requirements above.

When the SDK is used, it extracts metadata from request headers (see `greennode_agentbase.runtime.models`):
  - `X-GreenNode-AgentBase-Session-Id` → `context.session_id` (**required** when agent uses short-term memory / checkpointer)
  - `X-GreenNode-AgentBase-User-Id` → `context.user_id` (**required** when agent uses short-term memory / checkpointer or long-term memory; also required for delegated API key or OAuth2 3LO token). Maps to `actor_id` in memory operations.
  - `X-GreenNode-AgentBase-Request-Id` → `context.request_id` (auto-generated if not provided)
  - `X-GreenNode-AgentBase-Custom-*` → collected into `context.request_headers` (along with `Authorization`), for passing custom data to the agent

## Automatic runtime management (do not set manually)

- The IAM service account and Agent Identity are managed by the AgentBase runtime system and injected into the container as `GREENNODE_CLIENT_ID`, `GREENNODE_CLIENT_SECRET`, `GREENNODE_AGENT_IDENTITY`
- `GREENNODE_ENDPOINT_URL` is also auto-injected — contains the endpoint URL to call into the agent
- The SDK automatically uses these — no manual credential configuration needed in agent code
