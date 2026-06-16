# Multi-Memory Pattern

An agent may need multiple memory stores for different concerns. The Memory Service supports this — you can create and connect to multiple memories simultaneously.

## When to Use Multiple Memories

| Pattern | Use Case |
|---------|----------|
| **Single memory, multiple strategies** | One memory with both `SEMANTIC` and `USER_PREFERENCE` strategies — simpler setup, shared event expiry |
| **Multiple memories** | Separate stores for different concerns (e.g., conversation history vs domain knowledge vs user preferences) — independent expiry, separate namespaces |

## Trade-offs

- **Single memory**: Simpler to manage, one event expiry setting, strategies share the same events
- **Multiple memories**: Independent lifecycle and expiry per store, clearer separation of concerns, but more resources to manage

## SDK Example: Multiple Memory Clients

```python
from greennode_agentbase.memory import MemoryClient
from greennode_agentbase import IAMCredentials

creds = IAMCredentials()  # auto-loads from env or .greennode.json

# Conversation history (short-lived events)
history_client = MemoryClient(memory_id="mem_history", iam_credentials=creds)

# Domain knowledge (long-lived facts)
knowledge_client = MemoryClient(memory_id="mem_knowledge", iam_credentials=creds)

# Use each client independently
await history_client.create_event_async(...)
results = await knowledge_client.search_memory_records_async(...)
```

## LangChain Integration with Multiple Memories

```python
from greennode_agent_bridge import AgentBaseMemoryEvents

# Checkpointer for conversation state (short-term)
checkpointer = AgentBaseMemoryEvents(memory_id="mem_history")

# For long-term knowledge retrieval, use tool-based MemoryClient SDK calls
# (see references/langchain.md for @tool examples with remember/recall)
agent = create_agent(llm, tools=[remember_tool, recall_tool, ...], checkpointer=checkpointer)
```

## LangGraph Integration with Multiple Memories

```python
from greennode_agent_bridge import AgentBaseMemoryEvents

# Checkpointer for conversation state (short-term)
checkpointer = AgentBaseMemoryEvents(memory_id="mem_history")

# For long-term knowledge retrieval, use tool-based MemoryClient SDK calls
# (see references/langgraph.md for tool-based long-term memory integration)
graph = builder.compile(checkpointer=checkpointer)
```
