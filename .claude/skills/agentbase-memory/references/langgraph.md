# LangGraph Integration with AgentBase Memory

The `greennode-agent-bridge[langgraph]` package provides `AgentBaseMemoryEvents` — a `CheckpointSaver` that persists LangGraph checkpoints as events in AgentBase Memory (short-term memory / conversation persistence).

For long-term memory (semantic facts), use **tool-based calls** via the `MemoryClient` SDK.

## Install

```bash
pip install "greennode-agent-bridge[langgraph]"
```

## Key Design Principles

- `actor_id` — retrieved from `langgraph.config.get_config()` at runtime (set via `configurable` in `graph.invoke`). **Do NOT expose as a tool parameter** — the LLM should not decide which user's memory to access.
- `strategy_id` — fixed app-level config (`MEMORY_STRATEGY_ID` env var). **Do NOT expose as a tool parameter** — it's a deployment-time setting, not a per-call decision.

## Full LangGraph Integration Example

```python
import os
import asyncio
from typing import Annotated

from langchain_openai import ChatOpenAI
from langchain_core.tools import tool
from langgraph.graph import StateGraph, START, END
from langgraph.graph.message import add_messages
from langgraph.prebuilt import ToolNode, tools_condition
from langgraph.config import get_config
from typing_extensions import TypedDict

from greennode_agent_bridge import AgentBaseMemoryEvents
from greennode_agentbase.memory import MemoryClient
from greennode_agentbase.memory.models import MemoryRecordSearchRequest

# --- Configuration ---
MEMORY_ID = os.environ.get("AGENTBASE_MEMORY_ID", "mem_abc123")
MEMORY_STRATEGY_ID = os.environ.get("MEMORY_STRATEGY_ID", "default")
memory_client = MemoryClient()


# --- Helpers for actor_id and namespace ---

def _get_actor_id() -> str:
    """Get actor_id from LangGraph configurable (set during graph.invoke)."""
    config = get_config()
    return config["configurable"].get("actor_id", "default")


def _build_namespace(actor_id: str) -> str:
    """Build memory namespace from strategy_id (app config) and actor_id (runtime config)."""
    return f"/strategies/{MEMORY_STRATEGY_ID}/actors/{actor_id}"


# --- Long-Term Memory Tools (SDK) ---

@tool
async def remember(fact: str) -> str:
    """Store a fact in long-term memory for later retrieval.

    Args:
        fact: The fact or information to remember.
    """
    namespace = _build_namespace(_get_actor_id())
    await memory_client.insert_memory_records_directly_async(
        id=MEMORY_ID,
        namespace=namespace,
        request=[fact],
    )
    return f"Remembered: {fact}"


@tool
async def recall(query: str) -> str:
    """Search long-term memory for facts relevant to a query.

    Args:
        query: Natural language search query.
    """
    namespace = _build_namespace(_get_actor_id())
    results = await memory_client.search_memory_records_async(
        id=MEMORY_ID,
        namespace=namespace,
        request=MemoryRecordSearchRequest(query=query, limit=100),
    )
    if not results:
        return "No relevant memories found."
    return "\n".join(f"- {r.memory} (score: {r.score:.2f})" for r in results)


# --- Short-Term Memory (Checkpointer) ---
checkpointer = AgentBaseMemoryEvents(memory_id=MEMORY_ID)


# --- Define Graph State ---
class State(TypedDict):
    messages: Annotated[list, add_messages]


# --- Define Graph Nodes ---
llm = ChatOpenAI(model="gpt-4o-mini").bind_tools([remember, recall])


def chatbot(state: State):
    """Main chatbot node."""
    return {"messages": [llm.invoke(state["messages"])]}


# --- Build and Compile Graph ---
builder = StateGraph(State)
builder.add_node("chatbot", chatbot)
builder.add_node("tools", ToolNode([remember, recall]))
builder.add_edge(START, "chatbot")
builder.add_conditional_edges("chatbot", tools_condition)
builder.add_edge("tools", "chatbot")

# Compile with checkpointer for conversation persistence
graph = builder.compile(checkpointer=checkpointer)


# --- Run the Graph ---
def chat(user_message: str, actor_id: str = "user-1", session_id: str = "session-1"):
    """Send a message and get a response with memory."""
    config = {
        "configurable": {
            "thread_id": session_id,      # Maps to session ID in AgentBase
            "actor_id": actor_id,          # Maps to actor ID in AgentBase
        }
    }
    result = graph.invoke({"messages": [{"role": "user", "content": user_message}]}, config)
    return result["messages"][-1].content


# Example usage
if __name__ == "__main__":
    print(chat("Hi, I'm a Python developer from Ho Chi Minh City"))
    print(chat("What do you know about me?"))
```

## Minimal Checkpointer-Only Example

```python
from greennode_agent_bridge import AgentBaseMemoryEvents

checkpointer = AgentBaseMemoryEvents(memory_id="mem_abc123")

# Use with any LangGraph graph
graph = builder.compile(checkpointer=checkpointer)

# The thread_id in config maps to session_id, and actor_id maps to the actor
result = graph.invoke(
    {"messages": [{"role": "user", "content": "Hello"}]},
    {"configurable": {"thread_id": "session-1", "actor_id": "user-1"}},
)
```

## Long-Term Memory Tool Patterns

### Auto-recall on each turn

Add a node that automatically recalls relevant memories before the chatbot responds:

```python
async def recall_memories(state: State, config):
    """Auto-recall relevant memories before responding."""
    actor_id = config["configurable"].get("actor_id", "default")
    last_message = state["messages"][-1].content if state["messages"] else ""

    if not last_message:
        return state

    try:
        namespace = _build_namespace(actor_id)
        results = await memory_client.search_memory_records_async(
            id=MEMORY_ID,
            namespace=namespace,
            request=MemoryRecordSearchRequest(query=last_message, limit=5),
        )
        if results:
            facts = [r.memory for r in results]
            memory_context = "Relevant memories:\n" + "\n".join(f"- {f}" for f in facts)
            from langchain_core.messages import SystemMessage
            return {"messages": [SystemMessage(content=memory_context)]}
    except Exception:
        pass  # Gracefully handle memory service errors
    return state


# Add recall node before chatbot
builder.add_node("recall", recall_memories)
builder.add_edge(START, "recall")
builder.add_edge("recall", "chatbot")
```
