# Project Scaffolding (init)

Scaffold a new GreenNode AgentBase agent project. Use this section when running `init` directly, or when called from Step 2 of the wizard.

### Interaction Guidelines

- **Guide first, act only when asked** — if the user asks "how to" scaffold or set up an agent project, respond with instructions and guidance only. Do NOT create files or directories unless they explicitly ask you to do it for them (e.g., "create a new agent project", "scaffold it for me").
- **Confirm before executing (HARD GATE)** — before creating the project, present a summary of all choices (project name, framework, directory location) and ask the user to confirm. Do NOT auto-execute. Only proceed when the user responds with an explicit confirmation keyword: `yes`, `confirm`, `ok`, `approve`, `proceed`, `go ahead`, `do it`, `lgtm`, or equivalent affirmative. If the user responds with ANYTHING ELSE (parameter changes, questions, corrections, additional info, or ambiguous text), treat it as adjustment input — update the summary and re-present for confirmation again. NEVER interpret a non-confirmation response as approval.
- **Never auto-decide parameters** — when a choice is required (e.g., project name, framework type), always ask the user. You may recommend options, but never auto-select or impose values without the user's explicit agreement.
- **Present options, let user choose** — when there are multiple choices (e.g., Basic/LangChain/LangGraph), list the available options with descriptions and let the user pick. Do not make the choice for them.

### Init Step 1: Gather Input

- **Project name**: Use `$ARGUMENTS[1]` if provided (the argument after `init`). Otherwise, ask the user for a project name (lowercase, hyphens allowed, no spaces). If the user enters a name with spaces, uppercase, or special characters, sanitize it (lowercase, replace spaces with hyphens, remove special chars) and confirm with the user before proceeding. The project name is used for naming only (README, state file, Docker image tag) — files are created in the current working directory.
- **Python version**: Ask the user which Python version to use for the Docker base image (default: `3.13-slim`). Common options: `3.11-slim`, `3.12-slim`, `3.13-slim`. Use the chosen version in the Dockerfile `FROM` line.
- **Framework**: Check `$ARGUMENTS` for `--langchain`, `--langchain-memory`, `--langgraph`, `--langgraph-memory`, or `--custom`. If none is provided, ask the user to choose:
  - **Basic** - No AI framework, simple request/response agent (good starting point for any custom integration)
  - **LangChain** - Agent with tools via LangChain, uses GreenNode AI Platform LLM
  - **LangChain + Memory** - LangChain agent with built-in AgentBase Memory integration (short-term: checkpointer `AgentBaseMemoryEvents` + long-term: tool-based `MemoryClient` SDK with `remember`/`recall` tools)
  - **LangGraph** - Stateful graph agent with LangGraph, uses GreenNode AI Platform LLM
  - **LangGraph + Memory** - LangGraph agent with built-in AgentBase Memory integration (short-term: checkpointer `AgentBaseMemoryEvents` + long-term: tool-based `MemoryClient` SDK with `remember`/`recall` tools)
  - **Custom** - For any other framework (CrewAI, AutoGen, OpenAI SDK, etc.). Uses Basic template as the starting point — the user adds their own framework dependencies to `requirements.txt` and implements their logic in `main.py`. The only requirement is that the agent uses `greennode-agentbase` for the HTTP server (`GreenNodeAgentBaseApp`).

  **Important**: If the user mentions a specific framework that is NOT LangChain or LangGraph, recommend the **Custom** option and help them add their framework's dependencies. Do NOT force LangChain/LangGraph on users who want a different framework.

### Init Step 2: Check Current Directory

**All files are created in the current working directory (CWD).** Do NOT create a subdirectory for the project.

Before creating files, check if the CWD already contains any project files (`main.py`, `Dockerfile`, `requirements.txt`):
- If files exist, warn the user: "The current directory already contains project files (main.py, Dockerfile, etc.). Continuing will overwrite them. Proceed?"
- Only continue if the user confirms.

**CRITICAL**: Never create a subdirectory named after the project. The user is expected to already be in the correct directory (e.g., they ran `mkdir my-agent && cd my-agent` before invoking this skill). All files go directly in CWD.

### Init Step 3: Create Files

#### 3a. `main.py` - Agent Entrypoint

```python
import os
from datetime import datetime
from dotenv import load_dotenv
from greennode_agentbase import (
    GreenNodeAgentBaseApp,
    RequestContext,
    PingStatus,
)

load_dotenv()

app = GreenNodeAgentBaseApp()


@app.entrypoint
def handler(payload: dict, context: RequestContext) -> dict:
    """Main agent entrypoint.

    Args:
        payload: JSON body from POST /invocations
        context: Request metadata (session_id, user_id, request_headers)
    """
    message = payload.get("message", "Hello")
    return {
        "status": "success",
        "message": message,
        "timestamp": datetime.now().isoformat(),
        "session_id": context.session_id,
    }


@app.ping
def health_check() -> PingStatus:
    """Custom health check for GET /health endpoint."""
    return PingStatus.HEALTHY


if __name__ == "__main__":
    app.run(port=8080, host="0.0.0.0")
```

#### 3b. `Dockerfile`

```dockerfile
FROM python:{{PYTHON_VERSION}}
# Replace {{PYTHON_VERSION}} with the user's chosen version from Step 1 (e.g., 3.13-slim)
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
EXPOSE 8080
CMD ["python", "main.py"]
```

#### 3c. `requirements.txt`

For a **basic** project:
```
greennode-agentbase
python-dotenv
```

For a **LangChain** project:
```
greennode-agentbase
# Note: langchain v1.1.x removed create_agent from agents module.
# Pin >=1.2.0 where it was restored.
langchain>=1.2.0,<2.0.0
langchain-openai>=1.1.0,<2.0.0
python-dotenv
```

For a **LangChain + Memory** project:
```
greennode-agentbase
greennode-agent-bridge
langchain>=1.2.0,<2.0.0
langgraph>=1.0.0,<2.0.0
langchain-openai>=1.1.0,<2.0.0
python-dotenv
```

For a **LangGraph** project:
```
greennode-agentbase
greennode-agent-bridge[langgraph]
langgraph>=1.0.0,<2.0.0
langchain-openai>=1.1.0,<2.0.0
python-dotenv
```

For a **LangGraph + Memory** project (same as LangGraph):
```
greennode-agentbase
greennode-agent-bridge[langgraph]
langgraph>=1.0.0,<2.0.0
langchain-openai>=1.1.0,<2.0.0
python-dotenv
```

#### 3d. `.greennode.json` - Configuration Template

```json
{
  "client_id": "",
  "client_secret": "",
  "agent_identity": ""
}
```

#### 3e. `.env.example`

For a **basic** project:
```
GREENNODE_CLIENT_ID=
GREENNODE_CLIENT_SECRET=
# Optional: only needed if using agent identity features
GREENNODE_AGENT_IDENTITY=
```

For a **LangChain** or **LangGraph** project:
```
GREENNODE_CLIENT_ID=
GREENNODE_CLIENT_SECRET=
GREENNODE_AGENT_IDENTITY=
# LLM provider config (any OpenAI-compatible provider)
# For GreenNode AIP: use /agentbase-llm to get API key and set LLM_BASE_URL=https://maas-llm-aiplatform-hcm.api.vngcloud.vn/v1
# For OpenAI: set LLM_BASE_URL=https://api.openai.com/v1
# For Ollama: set LLM_BASE_URL=http://localhost:11434/v1 (no key needed)
LLM_API_KEY=
LLM_BASE_URL=
LLM_MODEL=
```

For a **LangChain + Memory** or **LangGraph + Memory** project:
```
GREENNODE_CLIENT_ID=
GREENNODE_CLIENT_SECRET=
GREENNODE_AGENT_IDENTITY=
# LLM provider config (any OpenAI-compatible provider)
LLM_API_KEY=
LLM_BASE_URL=
LLM_MODEL=
MEMORY_ID=
```

#### 3f. `.gitignore`

```
__pycache__/
*.py[cod]
.env
.greennode.json
.agentbase/
.agentbase-state.json
*.credentials.json
.venv/
venv/
*.egg-info/
dist/
build/
```

#### 3g. `.dockerignore`

```
.venv/
venv/
__pycache__/
*.py[cod]
.env
.env.*
.greennode.json
.agentbase/
.agentbase-state.json
*.credentials.json
.git/
.gitignore
*.md
```

### Init Step 4: Framework-Specific Setup

Apply the framework-specific setup based on the user's choice in Step 1. **Exactly one** of the following sub-steps applies:

#### 4a. Basic (no framework replacement needed)

The `main.py` created in Step 3 IS the Basic template — no replacement needed. The project is ready to use as-is. The user can add their logic directly in the `handler` function.

#### 4b. Custom (use Basic template + help add framework dependencies)

The `main.py` from Step 3 is used as the starting point. Help the user:
1. Add their framework's dependencies to `requirements.txt` (e.g., `crewai`, `autogen`, `openai`, etc.)
2. Modify `main.py` to integrate their framework while keeping the `GreenNodeAgentBaseApp` HTTP server and the `GET /health` endpoint intact
3. The only hard requirement is: the agent MUST use `greennode-agentbase` for the HTTP server (`GreenNodeAgentBaseApp`) and expose `GET /health` returning 200

#### 4c. LangChain (replace main.py with LangChain template)

If the user chose **LangChain**, replace `main.py` with the template in `assets/langchain_main.py`. Read the file and use its contents as the `main.py` for the project.

If the user chose **LangChain + Memory**, replace `main.py` with the template in `assets/langchain_memory_main.py`. Read the file and use its contents as the `main.py` for the project. This template includes `AgentBaseMemoryEvents` (CheckpointSaver for short-term conversation persistence) and tool-based long-term memory via `MemoryClient` SDK (`remember`/`recall` tools). The user will need to create a memory via `/agentbase-memory` and set the `MEMORY_ID` environment variable. The `MEMORY_STRATEGY_ID` env var defaults to `default` — it maps to the long-term memory strategy configured when creating the memory store.

#### 4d. LangGraph (replace main.py with LangGraph template)

If the user chose **LangGraph**, replace `main.py` with the template in `assets/langgraph_main.py`. Read the file and use its contents as the `main.py` for the project.

If the user chose **LangGraph + Memory**, replace `main.py` with the template in `assets/langgraph_memory_main.py`. Read the file and use its contents as the `main.py` for the project. This template includes `AgentBaseMemoryEvents` (CheckpointSaver for short-term conversation persistence) and tool-based long-term memory via `MemoryClient` SDK (`remember`/`recall` tools). The user will need to create a memory via `/agentbase-memory` and set the `MEMORY_ID` environment variable. The `MEMORY_STRATEGY_ID` env var defaults to `default` — it maps to the long-term memory strategy configured when creating the memory store.

### Init Step 5: Set Up Virtual Environment

After creating all files, set up the Python virtual environment **in the current working directory** (same directory as `main.py` and `requirements.txt`).

**Detect the user's OS** and use the appropriate activation command:

```bash
python3 -m venv venv   # macOS/Linux; use "python" instead of "python3" on Windows
```

**macOS/Linux:**
```bash
source venv/bin/activate
pip install -r requirements.txt
```

**Windows (PowerShell):**
```powershell
venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

**Windows (cmd.exe):**
```cmd
venv\Scripts\activate.bat
pip install -r requirements.txt
```

- Use `python3 -m venv venv` (standard `venv`, not `.venv`); on Windows, `python` may be needed instead of `python3`
- Run `pip install -r requirements.txt` inside the activated venv
- If `pip install` fails due to a missing package or version conflict, report the error to the user and ask how to proceed
- **IMPORTANT**: Do NOT `cd` into any subdirectory. The venv must be in the same directory as the project files.

### Init Step 6: Create README.md

Create a `README.md` with the following content (replace `{project_name}` with actual name).

For **LangChain** or **LangGraph** projects, include the "Configure LLM" section. For **basic** projects, omit it.

```markdown
# {project_name}

A GreenNode AgentBase agent.

## Prerequisites

- Python 3.10+
- A GreenNode IAM Service Account ([create one here](https://iam.console.vngcloud.vn/service-accounts))

## Setup

1. Create and activate a virtual environment:
   ```bash
   # macOS/Linux:
   python3 -m venv venv && source venv/bin/activate

   # Windows (PowerShell):
   python -m venv venv; venv\Scripts\Activate.ps1
   ```

2. Install dependencies:
   ```bash
   pip install -r requirements.txt
   ```

3. Configure credentials for **local development** (choose one method):

   **Option A** - Environment variables:
   ```bash
   cp .env.example .env
   # Edit .env with your credentials
   ```

   **Option B** - Config file (already created):
   Edit `.greennode.json` with your `client_id` and `client_secret` from your IAM Service Account.

   > **Note**: When deployed on AgentBase Runtime, the IAM service account and Agent Identity are managed by the runtime system and automatically available to the SDK — no manual credential configuration needed in the container.

4. (Optional, for local dev) Create an Agent Identity at https://aiplatform.console.vngcloud.vn/access-control and set `agent_identity` in `.greennode.json` or `GREENNODE_AGENT_IDENTITY` env var. On AgentBase Runtime, this is managed automatically by the runtime system.

## Configure LLM (LangChain/LangGraph only)

This project uses any OpenAI-compatible LLM provider. Set the following in `.env`:

```
LLM_API_KEY=your-api-key
LLM_BASE_URL=your-provider-base-url
LLM_MODEL=your-model-name
```

**Provider examples:**
- **GreenNode AIP**: Use `/agentbase-llm` to get an API key. Set `LLM_BASE_URL=https://maas-llm-aiplatform-hcm.api.vngcloud.vn/v1`
- **OpenAI**: Set `LLM_BASE_URL=https://api.openai.com/v1`, model e.g. `gpt-4o`
- **Ollama** (local): Set `LLM_BASE_URL=http://localhost:11434/v1` (no key needed)

**Production**: Use `/agentbase-identity` to store your API key on the platform and inject it at runtime.

## Run Locally

```bash
python3 main.py
```

The agent starts on `http://127.0.0.1:8080`.

Test it:
```bash
curl -X POST http://127.0.0.1:8080/invocations \
  -H "Content-Type: application/json" \
  -d '{"message": "Hello, agent!"}'
```

**Testing tips** — the SDK extracts metadata from request headers (defined in `greennode_agentbase.runtime.models`):
- If the agent uses **memory** (short-term or long-term), **both headers are required** — the agent will return an error without them:
  `-H "X-GreenNode-AgentBase-User-Id: test-user"` `-H "X-GreenNode-AgentBase-Session-Id: test-session-1"`
- If the agent uses **user identity features** (delegated API key, OAuth2 3LO token), pass a user header so credentials resolve correctly:
  `-H "X-GreenNode-AgentBase-User-Id: user-abc"`
- To pass **custom headers** to the agent, use the `X-GreenNode-AgentBase-Custom-` prefix. The SDK collects all headers with this prefix (plus `Authorization`) into `context.request_headers`:
  `-H "X-GreenNode-AgentBase-Custom-My-Key: some-value"`
  Then access in handler: `context.request_headers.get("X-GreenNode-AgentBase-Custom-My-Key")`

Health check:
```bash
curl http://127.0.0.1:8080/health
```

## Deploy to AgentBase Runtime

1. Build and push your Docker image (or use `/agentbase-deploy` skill)
2. Create a Runtime at https://aiplatform.console.vngcloud.vn/agent-runtime?tab=runtime
3. Create an Endpoint pointing to your Runtime

See the [AgentBase Console](https://aiplatform.console.vngcloud.vn) to manage runtimes, identities, and memory.

## Add Conversation Memory (Optional)

When you need conversation history or long-term memory, use `/agentbase-memory` to set up AgentBase Memory and integrate it with your agent.

## Project Structure

- `main.py` - Agent entrypoint with handler and health check
- `Dockerfile` - Container image definition
- `requirements.txt` - Python dependencies
- `.greennode.json` - AgentBase configuration
- `.env.example` - Environment variable template
```

### Init Step 7: Final Output

After creating all files, display a summary:

1. List all created files
2. Show next steps:
   - Virtual environment was created and dependencies were installed in Init Step 5
   - Reactivate venv when needed: `source venv/bin/activate` (macOS/Linux) or `venv\Scripts\Activate.ps1` (Windows PowerShell)
   - Configure credentials in `.greennode.json` or `.env`
   - For LangChain/LangGraph: set up LLM access with `/agentbase-llm` (list existing API keys or create one, browse models)
   - `python3 main.py`
3. Mention that `/agentbase-deploy` can be used later to deploy to AgentBase Runtime
4. Mention that `/agentbase-memory` can be used later to add conversation memory when needed
5. Mention that `/agentbase-identity` can be used to register an agent identity on the platform
6. Mention that `/agentbase-identity` can be used to store API keys securely on the platform for runtime injection
