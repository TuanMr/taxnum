# Memory Operations Reference

Full API details, SDK examples, CLI commands, and framework integration guides for the GreenNode AgentBase Memory Service.

**Script**: `bash .claude/skills/agentbase/scripts/memory.sh` (handles authentication, token refresh, response redaction, and error handling automatically)

---

## memory create
Creates a memory container with long-term memory strategies.

**Required fields**:
- `name` (string, 0-50 chars, pattern `^[a-zA-Z0-9._-]*$`)
- `description` (string)
- `eventExpiryDuration` (int, 1-365 days)
- `longTermMemoryStrategies` (array of strategy objects, each with):
  - `name` (string, min 1 char)
  - `type` (string, min 1 char) -- `SEMANTIC`, `USER_PREFERENCE`, or `CUSTOM`
  - `namespaceTemplate` (string, 0-50 chars, pattern `^[a-zA-Z0-9{}/._-]*$`)
  - `enableAutomaticMemoryRecordGeneration` (bool)
  - `customFactExtractionPrompt` (string, optional, max 10,000 chars) -- custom prompt for fact extraction. **Requires `type: "CUSTOM"`**

> **Note**: The `name` field is required by the v3 API but may not be present in the SDK's `LongTermMemoryStrategy` model. When using the SDK, pass `name` as an extra keyword argument or use the CLI for full API field support.

**CLI:**
```bash
bash .claude/skills/agentbase/scripts/memory.sh create \
  --name my-memory \
  --description "Agent memory" \
  --expiry-days 30 \
  --strategy-name semantic-facts \
  --strategy-type SEMANTIC \
  --namespace-template "/strategies/{memoryStrategyId}/actors/{actorId}" \
  --auto-generate
```

**SDK:**
```python
from greennode_agentbase.memory.models import MemoryCreateRequest, LongTermMemoryStrategy

request = MemoryCreateRequest(
    name="my-memory", description="Agent memory", eventExpiryDuration=30,
    longTermMemoryStrategies=[
        LongTermMemoryStrategy(name="semantic-facts", type="SEMANTIC",
            namespaceTemplate="/strategies/{memoryStrategyId}/actors/{actorId}",
            enableAutomaticMemoryRecordGeneration=True),
    ],
)
memory = await client.create_async(request=request)
```

Strategy types: `SEMANTIC` (general facts), `USER_PREFERENCE` (user habits), `CUSTOM` (custom extraction with `customFactExtractionPrompt`). Add multiple strategies by repeating in the array. **If user provides `customFactExtractionPrompt`, always set `type` to `CUSTOM`.**

---

## memory list
List all memories (paginated).

**Note**: Memory Service uses 1-indexed pagination (page=1 is first page).

**CLI:**
```bash
bash .claude/skills/agentbase/scripts/memory.sh list --page 1 --size 10
```

**SDK:**
```python
result = await client.list_async(page=1, size=10)
for memory in result.list_data:
    print(f"{memory.id}: {memory.name} ({memory.status})")
```

---

## memory get [memory-id]
Fetches memory info AND its long-term memory strategies in a single view. **Always call both APIs** to give the user the complete configuration they set during creation.

**CLI:**
```bash
# Get memory basic info
bash .claude/skills/agentbase/scripts/memory.sh get mem_abc123

# Get long-term memory strategies
bash .claude/skills/agentbase/scripts/memory.sh strategies mem_abc123
```

**SDK:**
```python
import asyncio
from greennode_agentbase.memory import MemoryClient

client = MemoryClient()

# Fetch both in parallel for efficiency
memory, strategies = await asyncio.gather(
    client.get_async(id="mem_abc123"),
    client.list_long_term_memory_strategies_async(id="mem_abc123"),
)

# Display complete memory detail
print(f"Name: {memory.name}")
print(f"Description: {memory.description}")
print(f"Status: {memory.status}")
print(f"Event expiry: {memory.event_expiry_duration} days")
print(f"Created: {memory.created_at}")
print(f"\nLong-Term Memory Strategies ({len(strategies)} configured):")
for s in strategies:
    print(f"  - ID: {s['id']}, Name: {s.get('name')}, Type: {s['type']}")
    print(f"    Namespace: {s.get('namespaceTemplate')}")
    print(f"    Auto-generate: {s.get('enableAutomaticMemoryRecordGeneration')}")
    if s.get('customFactExtractionPrompt'):
        print(f"    Custom prompt: {s['customFactExtractionPrompt']}")
```

**IMPORTANT:** When the user asks to "get", "show", "detail", or "inspect" a memory, ALWAYS present both the basic info and the strategies together. Do NOT show only the basic info without strategies — that gives an incomplete picture compared to what was configured at creation time.

---

## memory delete [memory-id]

**Before deleting**: Consider exporting or noting the resource configuration, as deletion is irreversible. There is no undo.

**CLI:**
```bash
bash .claude/skills/agentbase/scripts/memory.sh delete mem_abc123
```

**SDK:**
```python
await client.delete_async(id="mem_abc123")
```

---

## memory events - Manage Conversation Events

Events are individual conversation turns (user message, assistant response) stored in a memory.

### List Events

Optional query params: `fromTimestamp`, `toTimestamp`

> **Note:** Results are sorted by **descending** order (newest first) by default. Keep this in mind when processing sequential conversation data — you may need to reverse the list to get chronological order.

**CLI:**
```bash
bash .claude/skills/agentbase/scripts/memory.sh events list mem_abc123 user-1 session-1 --page 1 --size 20
```

**SDK:** See `references/advanced-operations.md` for SDK examples.

### Create Event

**Request body** (`EventCreateRequest`):
- `payload` (object, **required**):
  - `type` (string, **required**) — `"conversational"` or `"binary"` (see below)
  - `role` (string, optional) — message role (e.g. `"user"`, `"assistant"`) — **conversational only**
  - `message` (string, optional, max 100,000 chars) — text content — **conversational only**
  - `binaryData` (string, optional, max 1,048,576 bytes / 1MB) — binary data (e.g. base64-encoded) — **binary only**
- `eventTimestamp` (string, optional) — custom timestamp for the event (ISO 8601)

**Event types**:
- **`conversational`**: Standard chat turn with `role` + `message`. Used for conversation history and fact extraction.
- **`binary`**: Raw binary data via `binaryData` field. No `role` or `message`. Use for images, files, or other non-text payloads.

**CLI (conversational):**
```bash
bash .claude/skills/agentbase/scripts/memory.sh events create mem_abc123 user-1 session-1 \
  --type conversational --role user --message "What is the weather in Saigon?"
```

**SDK:** See `references/advanced-operations.md` for SDK examples.

### List Actors

**CLI:**
```bash
bash .claude/skills/agentbase/scripts/memory.sh actors mem_abc123
```

**SDK:** See `references/advanced-operations.md` for SDK examples.

For additional event operations (list sessions, delete event), see `references/advanced-operations.md`.

---

## memory records - Browse Memory Records

Memory records are distilled long-term facts extracted from conversation events.

**CLI:**
```bash
bash .claude/skills/agentbase/scripts/memory.sh records list mem_abc123 \
  --namespace "/strategies/strat_1/actors/user-1" --limit 100
```

**SDK:** See `references/advanced-operations.md` for SDK examples.

---

## memory search - Semantic Search Memory Records

Search memory records using natural language queries. The service performs vector similarity search.

**Request body**:
- `query` (string, required, min 1 char) -- natural language search query
- `limit` (int, optional, 5-200) -- max results to return
- `scoreThreshold` (float, optional, 0-1) -- minimum similarity score

**CLI:**
```bash
bash .claude/skills/agentbase/scripts/memory.sh records search mem_abc123 \
  --namespace "/strategies/strat_1/actors/user-1" \
  --query "user preferences about coffee" --limit 100 --threshold 0.5
```

**SDK:**
```python
from greennode_agentbase.memory import MemoryClient
from greennode_agentbase.memory.models import MemoryRecordSearchRequest

client = MemoryClient()

import asyncio
results = asyncio.run(
    client.search_memory_records_async(
        id="mem_abc123",
        namespace="/strategies/strat_1/actors/user-1",
        request=MemoryRecordSearchRequest(query="user preferences about coffee", limit=100),
    )
)
for record in results:
    print(f"[{record.score:.2f}] {record.memory}")
```

---

## memory generate - Generate Memory Records

Generate long-term memory records from conversation data using a configured strategy.

### From Session (existing events)

**CLI:**
```bash
bash .claude/skills/agentbase/scripts/memory.sh records generate-from-session mem_abc123 \
  --actor-id user-1 --session-id session-1 --strategy-id strat_1
```

**SDK:**
```python
await client.generate_memory_records_from_session_async(
    id="mem_abc123",
    actorId="user-1",
    sessionId="session-1",
    longTermMemoryStrategyId="strat_1",
)
```

For additional generation methods (from content, insert directly) and record deletion, see `references/advanced-operations.md`.

---

## memory integrate - Framework Integration

### Required Request Headers

When an agent uses AgentBase Memory, the following request headers are **required** and must be validated in the handler:

| Header | Maps to | Required for |
|--------|---------|-------------|
| `X-GreenNode-AgentBase-User-Id` | `context.user_id` -> `actor_id` | Short-term memory (checkpointer) AND long-term memory (tool-based) |
| `X-GreenNode-AgentBase-Session-Id` | `context.session_id` -> `thread_id` | Short-term memory (checkpointer) |

**The handler MUST return an error if these headers are missing** — do NOT fall back to default values like `"default-user"` or `"default-session"`. Silent defaults cause data mixing between users/sessions and are a source of hard-to-debug issues.

```python
@app.entrypoint
def handler(payload: dict, context: RequestContext) -> dict:
    # Validate required headers for memory integration
    if not context.user_id or not context.session_id:
        return {
            "status": "error",
            "error": "Missing required headers: X-GreenNode-AgentBase-User-Id and X-GreenNode-AgentBase-Session-Id are required when using memory.",
        }
    # ... proceed with agent invocation
```

### Short-Term Memory (Conversation Persistence)

Short-term memory uses **checkpointing** via the `greennode-agent-bridge` package. This persists LangGraph state (conversation history) as events in AgentBase Memory.

```bash
pip install "greennode-agent-bridge[langgraph]"
```

**LangChain** (`create_agent` accepts `checkpointer`):
```python
from greennode_agent_bridge import AgentBaseMemoryEvents

checkpointer = AgentBaseMemoryEvents(memory_id="mem_abc123")
agent = create_agent(llm, tools=[...], checkpointer=checkpointer)
```

**LangGraph**:
```python
from greennode_agent_bridge import AgentBaseMemoryEvents

checkpointer = AgentBaseMemoryEvents(memory_id="mem_abc123")
graph = builder.compile(checkpointer=checkpointer)
```

### Long-Term Memory (Semantic Facts)

Long-term memory uses a **tool-based approach with MemoryClient SDK**. This approach is more stable than using the SDK's store adaptor and gives full control over memory record operations.

**Important — `actor_id` and `strategy_id` management:**
- `actor_id` — **MUST** be retrieved from `langgraph.config.get_config()["configurable"]["actor_id"]` at runtime (set via `configurable` in `graph.invoke`). **Do NOT expose as a tool parameter** — the LLM should not decide which user's memory to access.
- `strategy_id` — **MUST** be a fixed app-level config (e.g. `MEMORY_STRATEGY_ID` env var). **Do NOT expose as a tool parameter** — it's a deployment-time setting, not a per-call decision.

See the reference files for complete integration examples:
- **LangChain**: Read `references/langchain.md` for `@tool` functions that call the Memory API directly (remember, recall) and a full agent example with checkpointer.
- **LangGraph**: Read `references/langgraph.md` for checkpointer + tool-based long-term memory integration.

---

## Long-Term Memory Strategies

Strategies are automatically shown when getting memory details (see `memory get` above). To list strategies independently, use:

**CLI:**
```bash
bash .claude/skills/agentbase/scripts/memory.sh strategies mem_abc123
```

See `references/advanced-operations.md` for SDK examples.

---

## Common Memory Workflows

1. **Auto-generation**: Create memory with `enableAutomaticMemoryRecordGeneration: true` -> log events -> records generated automatically
2. **Manual generation**: Create memory -> log events -> call `generate-from-session` or `generate-from-content` -> search records
3. **Direct insertion**: Create memory -> use `insert-directly` to add facts -> search records

---

## Important: URL Encoding

When using the SDK with query parameters that contain special characters (e.g. namespace paths like `/strategies/{strategyId}/actors/{actorId}`), the SDK handles encoding automatically. The CLI scripts also handle URL encoding internally.

In Python, use `urllib.parse.quote` or let the SDK handle encoding automatically.

## Multi-Memory Pattern

For using multiple memory stores simultaneously (separate stores for conversation history, domain knowledge, user preferences), see `references/multi-memory.md`.
