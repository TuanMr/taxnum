import os
from datetime import datetime
from typing import Annotated, TypedDict

from dotenv import load_dotenv
from langchain_openai import ChatOpenAI
from langchain_core.tools import tool
from langgraph.graph import StateGraph, START, END
from langgraph.graph.message import add_messages
from langgraph.prebuilt import ToolNode, tools_condition

from greennode_agentbase import (
    GreenNodeAgentBaseApp,
    RequestContext,
    PingStatus,
)
from greennode_agentbase.memory import MemoryClient
from greennode_agentbase.memory.models import MemoryRecordSearchRequest
from greennode_agent_bridge import AgentBaseMemoryEvents
from langgraph.config import get_config

load_dotenv()

app = GreenNodeAgentBaseApp()

# --- Memory Configuration ---
# Create a memory with: /agentbase-memory
# Set the memory ID here or via MEMORY_ID env var
MEMORY_ID = os.environ.get("MEMORY_ID", "")
if not MEMORY_ID:
    raise ValueError("MEMORY_ID environment variable is required for memory-enabled agents")

# Strategy ID for long-term memory namespace partitioning
# This is fixed per memory instance — do NOT pass as a tool parameter
MEMORY_STRATEGY_ID = os.environ.get("MEMORY_STRATEGY_ID", "default")

# CheckpointSaver: persists LangGraph graph state as events in AgentBase Memory
# This enables multi-turn conversations that survive restarts
checkpointer = AgentBaseMemoryEvents(memory_id=MEMORY_ID)

# MemoryClient: used by long-term memory tools to store/search semantic facts
memory_client = MemoryClient()

# --- LLM Configuration ---
# Uses any OpenAI-compatible LLM provider (GreenNode AIP, OpenAI, Ollama, etc.)
# Set LLM_BASE_URL, LLM_API_KEY, and LLM_MODEL in your .env file.
# For GreenNode AIP: use /agentbase-llm to manage API keys and browse models.
# For other providers: set the appropriate base URL and API key.
# Production: use /agentbase-identity to store API key, inject via @requires_api_key
LLM_MODEL = os.environ.get("LLM_MODEL", "")
LLM_BASE_URL = os.environ.get("LLM_BASE_URL", "")
LLM_API_KEY = os.environ.get("LLM_API_KEY", "")
if not LLM_MODEL or not LLM_BASE_URL or not LLM_API_KEY:
    raise ValueError(
        "LLM_MODEL, LLM_BASE_URL, and LLM_API_KEY environment variables are required. "
        "Set them in your .env file or use /agentbase-llm to get a platform API key."
    )

llm = ChatOpenAI(
    model=LLM_MODEL,
    base_url=LLM_BASE_URL,
    api_key=LLM_API_KEY,
)


# --- Long-Term Memory Tools (via MemoryClient SDK) ---
# actor_id: retrieved from LangGraph configurable (set in handler via context.user_id)
# strategy_id: app-level config (MEMORY_STRATEGY_ID), fixed per memory instance
# Neither should be exposed as tool parameters to avoid LLM hallucination


def _get_actor_id() -> str:
    """Get actor_id from LangGraph configurable (set during graph.invoke)."""
    config = get_config()
    return config["configurable"].get("actor_id", "default")


def _build_namespace(actor_id: str) -> str:
    """Build memory namespace from strategy_id (app config) and actor_id (runtime config)."""
    return f"/strategies/{MEMORY_STRATEGY_ID}/actors/{actor_id}"


@tool
def remember(fact: str) -> str:
    """Store a fact in long-term memory for later retrieval.

    Args:
        fact: The fact or information to remember.
    """
    namespace = _build_namespace(_get_actor_id())
    memory_client.insert_memory_records_directly(
        id=MEMORY_ID,
        namespace=namespace,
        request=[fact],
    )
    return f"Remembered: {fact}"


@tool
def recall(query: str) -> str:
    """Search long-term memory for facts relevant to a query.

    Args:
        query: Natural language search query.
    """
    namespace = _build_namespace(_get_actor_id())
    results = memory_client.search_memory_records(
        id=MEMORY_ID,
        namespace=namespace,
        request=MemoryRecordSearchRequest(query=query, limit=10),
    )
    if not results:
        return "No relevant memories found."
    return "\n".join(f"- {r.memory} (score: {r.score:.2f})" for r in results)


# Define graph state
class State(TypedDict):
    messages: Annotated[list, add_messages]


# Bind tools to LLM
llm_with_tools = llm.bind_tools([remember, recall])


# Define graph nodes
def chatbot(state: State) -> dict:
    """Chatbot node with tool-calling support."""
    return {"messages": [llm_with_tools.invoke(state["messages"])]}


# Build the graph
graph_builder = StateGraph(State)
graph_builder.add_node("chatbot", chatbot)
graph_builder.add_node("tools", ToolNode([remember, recall]))
graph_builder.add_edge(START, "chatbot")
graph_builder.add_conditional_edges("chatbot", tools_condition)
graph_builder.add_edge("tools", "chatbot")

# Compile with checkpointer for conversation persistence (short-term memory)
# Long-term memory is handled by remember/recall tools via MemoryClient SDK
graph = graph_builder.compile(checkpointer=checkpointer)


@app.entrypoint
def handler(payload: dict, context: RequestContext) -> dict:
    """Main agent entrypoint with LangGraph + Memory support.

    Args:
        payload: JSON body with "message"
        context: Request metadata (session_id, user_id, request_headers)
    """
    # Short-term memory (checkpointer) requires both user_id and session_id
    # to correctly persist and isolate conversation state per user per session.
    if not context.user_id or not context.session_id:
        return {
            "status": "error",
            "error": "Missing required headers: X-GreenNode-AgentBase-User-Id and X-GreenNode-AgentBase-Session-Id are required when using memory.",
        }

    message = payload.get("message", "Hello")

    # Map AgentBase context to LangGraph config
    # thread_id -> session persistence, actor_id -> per-user memory
    config = {
        "configurable": {
            "thread_id": context.session_id,
            "actor_id": context.user_id,
        }
    }

    result = graph.invoke({"messages": [("user", message)]}, config)
    ai_message = result["messages"][-1]

    return {
        "status": "success",
        "response": ai_message.content,
        "timestamp": datetime.now().isoformat(),
    }


@app.ping
def health_check() -> PingStatus:
    """Custom health check for GET /health endpoint."""
    return PingStatus.HEALTHY


if __name__ == "__main__":
    app.run(port=8080, host="0.0.0.0")
