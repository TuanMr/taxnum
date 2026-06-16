# LangChain Integration with AgentBase Memory

LangChain `create_agent` (v1.2+) natively supports the `checkpointer` parameter, enabling seamless integration with AgentBase Memory for conversation persistence.

For long-term memory (semantic facts), use tool-based calls via the `MemoryClient` SDK.

## Install

```bash
pip install greennode-agentbase langchain langgraph langchain-openai "greennode-agent-bridge[langgraph]"
```

## Long-Term Memory Tools via MemoryClient SDK

Create `@tool` functions that use the `MemoryClient` SDK.

**Key design principles:**
- `actor_id` — retrieved from `langgraph.config.get_config()` at runtime (set via `configurable` in `graph.invoke`). **Do NOT expose as a tool parameter** — the LLM should not decide which user's memory to access.
- `strategy_id` — fixed app-level config (`MEMORY_STRATEGY_ID` env var). **Do NOT expose as a tool parameter** — it's a deployment-time setting, not a per-call decision.

```python
import os
from langchain_core.tools import tool
from langgraph.config import get_config
from greennode_agentbase.memory import MemoryClient
from greennode_agentbase.memory.models import MemoryRecordSearchRequest

MEMORY_ID = os.environ.get("AGENTBASE_MEMORY_ID", "your-memory-id")
MEMORY_STRATEGY_ID = os.environ.get("MEMORY_STRATEGY_ID", "default")
memory_client = MemoryClient()


def _get_actor_id() -> str:
    """Get actor_id from LangGraph configurable (set during graph.invoke)."""
    config = get_config()
    return config["configurable"].get("actor_id", "default")


def _build_namespace(actor_id: str) -> str:
    """Build memory namespace from strategy_id (app config) and actor_id (runtime config)."""
    return f"/strategies/{MEMORY_STRATEGY_ID}/actors/{actor_id}"


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
```

## Full Agent Example

A complete LangChain agent with long-term memory tools and checkpoint-based conversation persistence:

```python
import os
from datetime import datetime

from langchain_openai import ChatOpenAI
from langchain.agents import create_agent
from langchain_core.tools import tool
from langgraph.config import get_config
from greennode_agentbase.memory import MemoryClient
from greennode_agentbase.memory.models import MemoryRecordSearchRequest

from greennode_agentbase import (
    GreenNodeAgentBaseApp,
    RequestContext,
    PingStatus,
)

app = GreenNodeAgentBaseApp()

MEMORY_ID = os.environ.get("AGENTBASE_MEMORY_ID", "your-memory-id")
MEMORY_STRATEGY_ID = os.environ.get("MEMORY_STRATEGY_ID", "default")
memory_client = MemoryClient()

llm = ChatOpenAI(
    model=os.environ.get("LLM_MODEL", "openai/gpt-4o-mini"),
    base_url=os.environ.get("AIP_BASE_URL", "https://maas-llm-aiplatform-hcm.api.vngcloud.vn/v1"),
    api_key=os.environ.get("AIP_API_KEY", ""),
)


def _get_actor_id() -> str:
    """Get actor_id from LangGraph configurable (set during graph.invoke)."""
    config = get_config()
    return config["configurable"].get("actor_id", "default")


def _build_namespace(actor_id: str) -> str:
    return f"/strategies/{MEMORY_STRATEGY_ID}/actors/{actor_id}"


@tool
async def remember(fact: str) -> str:
    """Store a fact in long-term memory."""
    namespace = _build_namespace(_get_actor_id())
    await memory_client.insert_memory_records_directly_async(
        id=MEMORY_ID,
        namespace=namespace,
        request=[fact],
    )
    return f"Remembered: {fact}"


@tool
async def recall(query: str) -> str:
    """Search long-term memory for relevant facts."""
    namespace = _build_namespace(_get_actor_id())
    results = await memory_client.search_memory_records_async(
        id=MEMORY_ID,
        namespace=namespace,
        request=MemoryRecordSearchRequest(query=query, limit=100),
    )
    if not results:
        return "No relevant memories found."
    return "\n".join(f"- {r.memory} (score: {r.score:.2f})" for r in results)


# --- Checkpointer for short-term memory (conversation persistence) ---
from greennode_agent_bridge import AgentBaseMemoryEvents

checkpointer = AgentBaseMemoryEvents(memory_id=MEMORY_ID)

agent = create_agent(
    llm,
    tools=[remember, recall],
    system_prompt=(
        "You are a helpful assistant with long-term memory. "
        "Use 'remember' to store important facts about the user. "
        "Use 'recall' to search for previously stored facts."
    ),
    checkpointer=checkpointer,  # Short-term: persist conversation state
)


@app.entrypoint
def handler(payload: dict, context: RequestContext) -> dict:
    # Short-term memory (checkpointer) requires both user_id and session_id
    # to correctly persist and isolate conversation state per user per session.
    if not context.user_id or not context.session_id:
        return {
            "status": "error",
            "error": "Missing required headers: X-GreenNode-AgentBase-User-Id and X-GreenNode-AgentBase-Session-Id are required when using memory.",
        }

    message = payload.get("message", "Hello")
    result = agent.invoke(
        {"messages": [{"role": "user", "content": message}]},
        config={
            "configurable": {
                "thread_id": context.session_id,
                "actor_id": context.user_id,
            }
        },
    )
    ai_message = result["messages"][-1]
    return {
        "status": "success",
        "response": ai_message.content,
        "timestamp": datetime.now().isoformat(),
    }


@app.ping
def health_check() -> PingStatus:
    return PingStatus.HEALTHY


if __name__ == "__main__":
    app.run(port=8080, host="0.0.0.0")
```

## When to Use LangGraph Instead

LangChain `create_agent` with `checkpointer` is sufficient for most use cases. Consider LangGraph directly when you need:
- **Custom graph topologies** (branching, cycles, conditional edges)
- **Human-in-the-loop** workflows with `interrupt_before`/`interrupt_after`
- **Fine-grained control** over state management and node execution

For simple tool-calling agents with memory, LangChain + checkpointer + tools is the recommended approach. See `langgraph.md` for LangGraph-specific integration details.
