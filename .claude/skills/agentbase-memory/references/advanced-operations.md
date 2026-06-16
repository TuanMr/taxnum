# Advanced Memory Operations

## Event SDK Examples

### List Events (SDK)

```python
result = await client.list_events_async(
    id="mem_abc123", actorId="user-1", sessionId="session-1", page=1, size=20
)
for event in result.list_data:
    print(f"[{event.role}] {event.content}")
```

### Create Event (SDK)

```python
from greennode_agentbase.memory.models import EventCreateRequest, ChatMessage

request = EventCreateRequest(
    payload=ChatMessage(role="user", content="What is the weather in Saigon?")
)
await client.create_event_async(
    id="mem_abc123", actorId="user-1", sessionId="session-1", request=request
)
```

> **Note**: The SDK uses `ChatMessage(role=..., content=...)` which maps to the API's `EventPayload(type=..., role=..., message=...)`. The SDK handles the field mapping automatically.

---

## Browse Memory Records (SDK)

```python
from greennode_agentbase.memory import MemoryClient

client = MemoryClient()

import asyncio
records = asyncio.run(
    client.list_memory_records_async(
        id="mem_abc123",
        namespace="/strategies/strat_1/actors/user-1",
    )
)
for record in records:
    print(f"[{record.id}] {record.memory} (score: {record.score})")
```

---

## Generate Memory Records from Content (ad-hoc messages)

**CLI:**
```bash
bash .claude/skills/agentbase/scripts/memory.sh records generate-from-content mem_abc123 \
  --strategy-id strat_1 --actor-id user-1 --session-id session-1 \
  --messages-file /path/to/messages.json
```

The messages file should contain a JSON array of chat messages:
```json
[
  {"role": "user", "content": "I always drink iced coffee in the morning"},
  {"role": "assistant", "content": "Noted! You prefer iced coffee for your morning routine."}
]
```

**Python (SDK):**
```python
import asyncio
from greennode_agentbase.memory import MemoryClient
from greennode_agentbase.memory.models import ChatMessage

client = MemoryClient()

result = asyncio.run(
    client.generate_memory_records_from_content_async(
        id="mem_abc123",
        longTermMemoryStrategyId="strat_1",
        actorId="user-1",
        sessionId="session-1",
        request=[
            ChatMessage(role="user", content="I always drink iced coffee in the morning"),
            ChatMessage(role="assistant", content="Noted! You prefer iced coffee for your morning routine."),
        ],
    )
)
```

---

## Insert Memory Records Directly (manual facts)

**CLI:**
```bash
bash .claude/skills/agentbase/scripts/memory.sh records insert mem_abc123 \
  --namespace "/strategies/strat_1/actors/user-1" \
  --records "User prefers Vietnamese coffee,User is based in Ho Chi Minh City,User works in software engineering"
```

**Python (SDK):**
```python
import asyncio
from greennode_agentbase.memory import MemoryClient

client = MemoryClient()

result = asyncio.run(
    client.insert_memory_records_directly_async(
        id="mem_abc123",
        namespace="/strategies/strat_1/actors/user-1",
        request=[
            "User prefers Vietnamese coffee",
            "User is based in Ho Chi Minh City",
        ],
    )
)
```

---

## Delete a Memory Record

**CLI:**
```bash
bash .claude/skills/agentbase/scripts/memory.sh records delete mem_abc123 rec_789
```

---

## Delete an Event

**CLI:**
```bash
bash .claude/skills/agentbase/scripts/memory.sh events delete mem_abc123 user-1 session-1 evt_456
```

---

## List Actors

**CLI:**
```bash
bash .claude/skills/agentbase/scripts/memory.sh actors mem_abc123
```

**Python (SDK):** No direct method available. Use CLI above.

---

## List Sessions for an Actor

**CLI:**
```bash
bash .claude/skills/agentbase/scripts/memory.sh sessions mem_abc123 user-1
```

---

## Long-Term Memory Strategies

List strategies configured for a memory:

**CLI:**
```bash
bash .claude/skills/agentbase/scripts/memory.sh strategies mem_abc123
```

**Python (SDK):**
```python
import asyncio
from greennode_agentbase.memory import MemoryClient

client = MemoryClient()

result = asyncio.run(
    client.list_long_term_memory_strategies_async(id="mem_abc123")
)
for s in result:
    print(f"ID: {s['id']}, Type: {s['type']}, Template: {s.get('namespaceTemplate')}")
```
