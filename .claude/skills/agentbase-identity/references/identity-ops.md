# Identity Operations Reference

Full API details, SDK examples, and CLI commands for agent identity CRUD operations on the GreenNode AgentBase Identity Service.

**Script**: `bash .claude/skills/agentbase/scripts/identity.sh` (handles authentication, token refresh, response redaction, and error handling automatically)

---

## identity create [name]
Create a new agent identity.

- **Body fields**:
  - `name` (string, **required**, 3-50 chars, pattern: `^[a-zA-Z0-9_-]+$`)
  - `description` (string, optional, 0-500 chars)
  - `allowedReturnUrls` (array of strings, optional, max 10 items, each 0-1000 chars) — URLs that are allowed as `returnUrl` in delegated request-key and OAuth2 3LO token flows. **If the agent uses delegated or 3LO flows, the `returnUrl` passed to those APIs must be in this list.**
- Ask for `name` if not provided. Optionally ask for `description` and `allowedReturnUrls`.

**SDK (recommended)**:
```python
from greennode_agentbase import IdentityClient, IAMCredentials
from greennode_agentbase.identity import CreateAgentIdentityRequest

creds = IAMCredentials(client_id="...", client_secret="...")
client = IdentityClient(iam_credentials=creds)

# Async
identity = await client.create_agent_identity_async(
    request=CreateAgentIdentityRequest(
        name="my-agent",
        description="My agent identity",
        allowed_return_urls=["https://example.com/callback"],
    )
)
print(identity.name, identity.id)

# Sync
identity = client.create_agent_identity(
    request=CreateAgentIdentityRequest(name="my-agent")
)
```

Note: `IAMCredentials()` with no args will auto-load from env vars `GREENNODE_CLIENT_ID` / `GREENNODE_CLIENT_SECRET` or `.greennode.json`.

**CLI**:
```bash
bash .claude/skills/agentbase/scripts/identity.sh create --name my-agent --description "My agent" --allowed-urls "https://example.com/callback"
```

---

## identity list
List all agent identities (paginated).

- **Query params**: `page` (0-indexed), `size`, `sortBy`, `sortDirection`

**Note**: Identity Service uses 0-indexed pagination (page=0 is first page). This differs from Memory Service which uses 1-indexed pagination.

**SDK**:
```python
from greennode_agentbase import IdentityClient, IAMCredentials

client = IdentityClient(iam_credentials=IAMCredentials())
result = await client.list_agent_identities_async(page=0, size=20)
for identity in result.content:
    print(f"{identity.name} (id: {identity.id}, created: {identity.created_at})")
print(f"Total: {result.total_elements}, Pages: {result.total_pages}")
```

**CLI**:
```bash
bash .claude/skills/agentbase/scripts/identity.sh list --page 0 --size 20
```

---

## identity get [name]
Get details of a specific agent identity.

- Ask for `name` if not provided.

**SDK**:
```python
client = IdentityClient(iam_credentials=IAMCredentials())
identity = await client.get_agent_identity_async(name="my-agent")
print(f"Name: {identity.name}")
print(f"ID: {identity.id}")
print(f"Description: {identity.description}")
print(f"Allowed Return URLs: {identity.allowed_return_urls}")
print(f"Created: {identity.created_at}")
```

**CLI**:
```bash
bash .claude/skills/agentbase/scripts/identity.sh get my-agent
```

---

## identity update [name]
Update an existing agent identity.

- **Body fields**:
  - `description` (string, optional, 0-500 chars)
  - `allowedReturnUrls` (array of strings, optional, max 10 items, each 0-1000 chars) — URLs allowed as `returnUrl` in delegated request-key and OAuth2 3LO token flows
- Ask for `name` if not provided. Ask which fields to update.

**SDK**:
```python
from greennode_agentbase import IdentityClient, IAMCredentials
from greennode_agentbase.identity import UpdateAgentIdentityRequest

client = IdentityClient(iam_credentials=IAMCredentials())
identity = await client.update_agent_identity_async(
    name="my-agent",
    request=UpdateAgentIdentityRequest(
        description="Updated description",
        allowed_return_urls=["https://example.com/callback"],
    )
)
print(f"Updated: {identity.name}")
```

**CLI**:
```bash
bash .claude/skills/agentbase/scripts/identity.sh update my-agent --description "Updated description" --allowed-urls "https://example.com/callback"
```

---

## identity delete [name]

**Before deleting**: Consider exporting or noting the resource configuration, as deletion is irreversible. There is no undo.

Delete an agent identity. This is irreversible -- confirm with the user before proceeding.

- Ask for `name` if not provided.

**SDK**:
```python
client = IdentityClient(iam_credentials=IAMCredentials())
await client.delete_agent_identity_async(name="my-agent")
```

**CLI**:
```bash
bash .claude/skills/agentbase/scripts/identity.sh delete my-agent
```

---

## Identity Response Model

`AgentIdentityResponse` fields:
- `id` (str) - Unique identifier
- `name` (str) - Identity name
- `description` (str, optional)
- `allowed_return_urls` (list[str], optional) - OAuth2 callback URLs
- `created_at` (datetime)
- `updated_at` (datetime)

---

## Relationship between Identity and Auth

Agent identity is a **required prerequisite** for retrieving secrets from auth providers. All secret retrieval operations require an agent identity name:

- `auth.sh apikey get-key` — retrieve stored API key
- `auth.sh delegated get-key` — request delegated key
- `auth.sh oauth2 get-m2m-token` — get M2M token
- `auth.sh oauth2 get-3lo-token` — get 3LO token

**Workflow**: Create an agent identity first (identity operations), then create auth providers and retrieve secrets using that identity (auth operations).
