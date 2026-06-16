---
name: agentbase-memory
description: "Add memory to AI agents — conversation history, semantic fact extraction, and long-term memory records. Covers creating memory stores, managing events/sessions, memory records, long-term memory strategies (SEMANTIC, USER_PREFERENCE, CUSTOM), and LangChain/LangGraph memory integration. DO NOT use for agent source code (use /agentbase-wizard), agent identity or outbound auth (use /agentbase-identity), platform LLM API keys (use /agentbase-llm), or runtime logs (use /agentbase-monitor)."
---

# AgentBase Memory Service

Manage memory stores for AI agents on the GreenNode AgentBase platform — conversation history (short-term events) and semantic fact extraction (long-term memory records). Parse the user's arguments to determine the operation and optional name/ID.

## Base URLs

- **Memory**: `https://agentbase.api.vngcloud.vn/memory`
- **Console (Memory)**: https://aiplatform.console.vngcloud.vn/memory

## Authentication & Endpoints

Read the shared auth setup reference at `/agentbase` skill's `references/auth-setup.md` for full IAM credential configuration. In brief: run `bash .claude/skills/agentbase/scripts/check_credentials.sh iam` to verify credentials are configured, then use `TOKEN=$(bash .claude/skills/agentbase/scripts/get_token.sh)` to obtain a token. **NEVER read `.greennode.json` or `.env` directly** — always use the helper scripts. On 401: re-run with `--force`. If `check_credentials.sh iam` returns MISSING, **STOP — you MUST read** the **"If Credentials Are Not Found"** section in `/agentbase` skill's `references/auth-setup.md` and follow it exactly. Do NOT skip this or provide your own credential setup instructions.

**IMPORTANT:** Before constructing any API URL, read `/agentbase` skill's `references/endpoints.md` for the domain validation whitelist. Only use domains listed there.

---

## Interaction Guidelines

- **Never assume API response structure** — always inspect the actual response first before extracting or filtering data. Do not guess field names.
- **Guide first, act only when asked** — if the user asks "how to" create memory or persist conversations, respond with instructions and guidance only. Do NOT execute API calls or create resources unless they explicitly ask you to do it for them.
- **Confirm before executing (HARD GATE)** — before performing any action (create, update, delete, retrieve, generate, search), present a clear summary of what will be done (including all parameters and values) and ask the user to confirm. Do NOT auto-execute. Only proceed when the user responds with an explicit confirmation keyword: `yes`, `confirm`, `ok`, `approve`, `proceed`, `go ahead`, `do it`, `ship it`, `lgtm`, or equivalent affirmative. If the user responds with ANYTHING ELSE (parameter changes, questions, corrections, additional info, or ambiguous text), treat it as adjustment input — update the plan and re-present the full summary for confirmation again. NEVER interpret a non-confirmation response as approval. For destructive operations (delete memory, delete event, delete memory record), additionally warn that the action is irreversible.
- **Never auto-decide parameters** — when an action requires parameters (e.g., memory name, strategy type, event expiry, namespace, actorId, sessionId), always ask the user for each required value. You may recommend sensible defaults or examples, but never auto-select or impose values without the user's explicit agreement.
- **Present options, let user choose** — when there are multiple choices (e.g., strategy type, operations), list the available options and let the user pick. Do not make the choice for them.
- **Dry-run support**: When user requests `--dry-run` or preview, show the exact API request (method, URL, headers, payload) and explain the expected outcome WITHOUT executing. Let user review before proceeding.
- **Always read full API response body** — when calling platform APIs, capture and read the full JSON response (not just status codes). This avoids misidentifying field names or data structures, ensures correct field extraction, and enables better error handling and debugging.

## Runtime Auto-Injection

When an agent is deployed on AgentBase Runtime, the IAM service account and Agent Identity are managed by the runtime system and automatically injected into the container as `GREENNODE_CLIENT_ID`, `GREENNODE_CLIENT_SECRET`, and `GREENNODE_AGENT_IDENTITY`. The SDK automatically uses these — no manual credential configuration needed in agent code. Memory operations and LangGraph bridge integrations all work automatically.

The IAM credentials and memory management described in this skill are for **local development** and **platform management** (creating/listing/updating resources from outside the runtime). See `/agentbase-deploy runtime` for details on runtime environment management.

---

# Memory Service

The Memory Service provides conversation history (short-term events) and semantic fact extraction (long-term memory records) for AI agents.

## Core Concepts

| Concept | Description | Lifetime |
|---------|-------------|----------|
| **Memory** | Top-level container that holds events and records | Permanent until deleted |
| **Event** | Single conversation turn (role + content) | Expires after `eventExpiryDuration` days |
| **Actor** | Participant identifier (user ID or agent ID) | Created on first event |
| **Session** | Conversation thread within an actor | Created on first event |
| **Memory Record** | Distilled long-term fact extracted from events | Permanent until deleted |
| **Long-Term Memory Strategy (LTMS)** | Extraction rules for generating memory records | Permanent, configured at memory creation |

### Strategy Types

- `SEMANTIC` - General semantic fact extraction
- `USER_PREFERENCE` - Extract user preferences and habits
- `CUSTOM` - Custom fact extraction with a user-defined prompt (`customFactExtractionPrompt`). **When using `customFactExtractionPrompt`, the type MUST be `CUSTOM`** — using `SEMANTIC` or `USER_PREFERENCE` with a custom prompt will silently ignore the prompt without any error. **Always validate**: if user provides a custom prompt, auto-correct `type` to `CUSTOM` and warn the user about the change. The custom prompt is **prepended** to the built-in extraction prompt, not a replacement.

### Namespace Template

Controls how memory records are partitioned. Default: `/strategies/{memoryStrategyId}/actors/{actorId}`

Available variables: `{memoryStrategyId}`, `{actorId}`, `{sessionId}`

> **Note on `actorId`**: The `actorId` represents the **end-user** (the person interacting with the agent), not the agent itself. Use any string that uniquely identifies the user (e.g. a user ID like `alice`, `user-123`). This allows the memory system to partition and recall facts per user. Do not confuse `actorId` with the agent's identity — for agent identity management, see `/agentbase-identity`.

## Memory Operations Summary

| Operation | Method | Endpoint |
|-----------|--------|----------|
| Create | `POST` | `/memories` |
| List | `GET` | `/memories?page=1&size=10` |
| Get | `GET` | `/memories/{id}` + `/memories/{id}/long-term-memory-strategies` |
| Delete | `DELETE` | `/memories/{id}` |
| List Events | `GET` | `/memories/{memoryId}/actors/{actorId}/sessions/{sessionId}/events` |
| Create Event | `POST` | `/memories/{memoryId}/actors/{actorId}/sessions/{sessionId}/events` |
| List Actors | `GET` | `/memories/{memoryId}/actors` |
| Browse Records | `GET` | `/memories/{memoryId}/memory-records?namespace=...&limit=100` |
| Search Records | `POST` | `/memories/{memoryId}/memory-records:search?namespace=...` |
| Generate from Session | `POST` | `/memories/{memoryId}/memory-records:generate-from-session?actorId=...&sessionId=...&longTermMemoryStrategyId=...` |
| Generate from Content | `POST` | `/memories/{memoryId}/memory-records:generate-from-content` |
| Insert Directly | `POST` | `/memories/{memoryId}/memory-records:insert-directly` |
| Delete Memory Record | `DELETE` | `/memories/{memoryId}/memory-records/{memoryRecordId}` |
| List Sessions | `GET` | `/memories/{memoryId}/actors/{actorId}/sessions` |
| Delete Event | `DELETE` | `/memories/{memoryId}/actors/{actorId}/sessions/{sessionId}/events/{eventId}` |
| List Strategies | `GET` | `/memories/{memoryId}/long-term-memory-strategies` |

**Note**: Memory Service uses 1-indexed pagination (page=1 is first page). This differs from Identity Service which uses 0-indexed pagination.

Read `references/memory-ops.md` for full API details, SDK examples, curl commands, and framework integration guides.

## Memory Instructions

1. Parse the user's argument to determine the operation.
2. If credentials are not configured, present the user with the two options (Auto create / I already have) as described in the Authentication section above.
3. For **create**: ask for each parameter individually — `name`, `description`, `eventExpiryDuration`, and strategy details (`name`, `type`, `namespaceTemplate`, `enableAutomaticMemoryRecordGeneration`, optionally `customFactExtractionPrompt`). If user provides `customFactExtractionPrompt`, always set `type` to `CUSTOM`.
4. For **get**: always fetch both basic info (`GET /memories/{id}`) and strategies (`GET /memories/{id}/long-term-memory-strategies`) to present a complete view.
5. For operations requiring `actorId`, `sessionId`, or `namespace`, ask the user for these values.
6. Show SDK examples by default. Show curl examples if user specifically asks or if working outside Python.
7. For framework integration (LangChain/LangGraph checkpointer, long-term memory tools): Quick start — for LangChain, use `AgentBaseMemoryEvents` as checkpointer via `create_agent(checkpointer=...)`. For LangGraph, use `builder.compile(checkpointer=...)`. For complete examples, **read `references/memory-ops.md`** for the integration section, and `references/langchain.md` / `references/langgraph.md` for complete examples. Do NOT provide integration code without reading these first.

---

# Troubleshooting

| Error | Cause | Fix |
|-------|-------|-----|
| 401 Unauthorized | Expired or invalid IAM token | Re-obtain token with valid credentials. Ensure `GREENNODE_CLIENT_ID` and `GREENNODE_CLIENT_SECRET` are set correctly (on AgentBase Runtime, these are auto-injected) |
| 403 Forbidden | Service account lacks permissions | Check IAM roles at https://iam.console.vngcloud.vn |
| 404 Not Found | Memory does not exist | Verify the memory ID exists with `GET /memories` |
| `.greennode.json` not found | Config file missing or wrong directory | Create `.greennode.json` with `client_id`, `client_secret` fields |
| Memory not found | Memory ID does not exist | Verify the memory ID exists with `GET /memories` |
| No records returned | Namespace mismatch or asynchronous processing | Check the namespace matches the strategy template. Records are generated asynchronously — wait a few seconds and retry |
| Events not appearing | Events expired or filtered out | Events expire after `eventExpiryDuration` days. Check the timestamp filters |
| Auto-generation not working | Strategy misconfigured | Verify `enableAutomaticMemoryRecordGeneration` is `true` on the strategy |
| "Missing required headers" error | Request missing `X-GreenNode-AgentBase-User-Id` or `X-GreenNode-AgentBase-Session-Id` | Include both headers in the request. Short-term memory requires `user_id` + `session_id`; long-term memory requires `user_id` (maps to `actor_id`) |
