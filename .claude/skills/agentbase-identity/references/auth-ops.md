# Auth Provider Operations Reference

Full API details, SDK examples, and CLI commands for outbound authentication provider management on the GreenNode AgentBase Identity Service.

**Script**: `bash .claude/skills/agentbase/scripts/auth.sh` (handles authentication, token refresh, response redaction, and error handling automatically)

**Note**: Apikey and OAuth2 secret values are auto-redacted by the scripts in command output.

### Safe Secret Input

All commands that accept secrets (`--apikey`, `--client-secret`) support two additional safe input methods to avoid exposing secrets in the LLM conversation context:

| Flag | Description | Example |
|------|-------------|---------|
| `--apikey-env ENV_VAR` | Read apikey from environment variable | `--apikey-env OPENAI_API_KEY` |
| `--apikey-file PATH` | Read apikey from file | `--apikey-file .secrets/openai.key` |
| `--client-secret-env ENV_VAR` | Read client secret from environment variable | `--client-secret-env GOOGLE_CLIENT_SECRET` |
| `--client-secret-file PATH` | Read client secret from file | `--client-secret-file .secrets/google.key` |

**Always prefer `--*-env` or `--*-file` over raw `--apikey`/`--client-secret`** to prevent secrets from appearing in the conversation.

---

## Provider Type 1: Static API Key (`apikey`)

Store a static API key (e.g., an OpenAI key) that agents can retrieve at runtime.

### auth apikey create [name]
- **Body**: `{"name": "...", "apikey": "sk-..."}`
- Name constraints: 3-50 chars, `^[a-zA-Z0-9_-]+$`
- `apikey` (string, max 1000 chars) -- the actual secret key to store
- Ask for `name` and `apikey` (prefer `--apikey-env` or `--apikey-file` for safe input).

**SDK**:
```python
from greennode_agentbase import IdentityClient, IAMCredentials
from greennode_agentbase.identity import CreateApikeyProviderRequest

client = IdentityClient(iam_credentials=IAMCredentials())
provider = await client.create_api_key_provider_async(
    request=CreateApikeyProviderRequest(name="openai-key", apikey="sk-...")
)
print(f"Created: {provider.name} (status: {provider.status})")
```

**CLI**:
```bash
# Safe: read from env var (preferred)
export OPENAI_API_KEY="sk-..."
bash .claude/skills/agentbase/scripts/auth.sh apikey create --name openai-key --apikey-env OPENAI_API_KEY

# Or from file
bash .claude/skills/agentbase/scripts/auth.sh apikey create --name openai-key --apikey-file .secrets/openai.key
```

### auth apikey list
- **Query params**: `page` (0-indexed), `size`, `sortBy`, `sortDirection`

**SDK**:
```python
client = IdentityClient(iam_credentials=IAMCredentials())
result = await client.list_api_key_providers_async(page=0, size=20)
for p in result.content:
    print(f"{p.name} (status: {p.status}, id: {p.id})")
```

**CLI**:
```bash
bash .claude/skills/agentbase/scripts/auth.sh apikey list --page 0 --size 20
```

### auth apikey get [name]

**SDK**:
```python
provider = await client.get_api_key_provider_async(name="openai-key")
print(f"Name: {provider.name}, Status: {provider.status}")
```

**CLI**:
```bash
bash .claude/skills/agentbase/scripts/auth.sh apikey get --name openai-key
```

### auth apikey update [name]
Update an existing API key provider (e.g., rotate the stored key).

- **Body**: `{"apikey": "sk-new-..."}`

**SDK**:
```python
from greennode_agentbase.identity import UpdateApikeyProviderRequest

provider = await client.update_api_key_provider_async(
    name="openai-key",
    request=UpdateApikeyProviderRequest(apikey="sk-new-...")
)
print(f"Updated: {provider.name}")
```

**CLI**:
```bash
bash .claude/skills/agentbase/scripts/auth.sh apikey update --name openai-key --apikey-env OPENAI_API_KEY
```

### auth apikey delete [name]

**Before deleting**: Consider exporting or noting the resource configuration, as deletion is irreversible. There is no undo.

- Confirm with the user before proceeding.

**SDK**:
```python
await client.delete_api_key_provider_async(name="openai-key")
```

**CLI**:
```bash
bash .claude/skills/agentbase/scripts/auth.sh apikey delete --name openai-key
```

### auth apikey retrieve-key [providerName] [agentName]
Retrieve the stored API key for a specific agent identity.

**SDK**:
```python
result = await client.get_api_key_for_agent_identity_async(
    provider_name="openai-key",
    agent_identity_name="my-agent",
)
print(f"API Key: {result.apikey}")
```

**CLI**:
```bash
bash .claude/skills/agentbase/scripts/auth.sh apikey get-key --provider openai-key --identity my-agent
```

For decorator usage examples (`@requires_api_key`), see `references/usage.md`.

---

## Provider Type 2: Delegated API Key (`delegated`)

Delegated keys enable user-federation flows where end-users provide their own API keys through a consent flow.

### auth delegated create [name]
- **Body**: `{"name": "..."}`
- Only requires a name (no key stored upfront -- keys come from end-users).

**SDK**:
```python
from greennode_agentbase.identity import CreateDelegatedApiKeyProviderRequest

provider = await client.create_delegated_api_key_provider_async(
    request=CreateDelegatedApiKeyProviderRequest(name="user-openai-key")
)
print(f"Created: {provider.name} (status: {provider.status})")
```

**CLI**:
```bash
bash .claude/skills/agentbase/scripts/auth.sh delegated create --name user-openai-key
```

### auth delegated list
- **Query params**: `page` (0-indexed), `size`, `sortBy`, `sortDirection`

**SDK**:
```python
result = await client.list_delegated_api_key_providers_async(page=0, size=20)
for p in result.content:
    print(f"{p.name} (status: {p.status})")
```

**CLI**:
```bash
bash .claude/skills/agentbase/scripts/auth.sh delegated list
```

### auth delegated get [name]

**SDK**:
```python
provider = await client.get_delegated_api_key_provider_async(name="user-openai-key")
```

**CLI**:
```bash
bash .claude/skills/agentbase/scripts/auth.sh delegated get --name user-openai-key
```

### auth delegated delete [name]

**Before deleting**: Consider exporting or noting the resource configuration, as deletion is irreversible. There is no undo.

- Confirm with user before proceeding.

**SDK**:
```python
await client.delete_delegated_api_key_provider_async(name="user-openai-key")
```

**CLI**:
```bash
bash .claude/skills/agentbase/scripts/auth.sh delegated delete --name user-openai-key
```

### auth delegated request-key [providerName] [agentIdentityName]
Request a delegated API key (triggers user-federation flow). For full API details, SDK examples, and decorator usage (`@requires_api_key` with `USER_FEDERATION` flow), see `references/usage.md`.

**CLI**:
```bash
bash .claude/skills/agentbase/scripts/auth.sh delegated get-key --provider user-openai-key --identity my-agent --agent-user-id user123 --return-url "https://example.com/callback"
```

- `customState` (string, optional, max 100 chars) -- custom state to pass through the delegation flow

> **IMPORTANT**: The `returnUrl` parameter **must be included in the `allowedReturnUrls` list** of the agent identity being used. If the URL is not whitelisted in the agent identity, the API will reject the request. Use `/agentbase-identity` to add the URL to the identity's `allowedReturnUrls` if needed.

---

## Provider Type 3: OAuth2 (`oauth2`)

Register external OAuth2 providers (e.g., Google, GitHub, Slack) for agent-to-service authentication.

### auth oauth2 create [name]
- **Body**: `{"name": "...", "clientId": "...", "clientSecret": "...", "authorizationUrl": "...", "tokenUrl": "..."}`
- Name constraints: 3-50 chars, `^[a-zA-Z0-9_-]+$`
- `clientId` (string, 1-100 chars), `clientSecret` (string, 1-100 chars), `authorizationUrl` (string, 0-1000 chars), `tokenUrl` (string, 0-1000 chars)
- Ask for all required fields: name, clientId, clientSecret, authorizationUrl, tokenUrl.

> **IMPORTANT (3LO setup)**: After creating an OAuth2 provider, if the user intends to use the **3-legged OAuth (3LO)** flow, they **must whitelist the platform's callback URL** on their external OAuth2 provider's configuration (e.g., Google Cloud Console -> Authorized redirect URIs, GitHub OAuth App -> Authorization callback URL). The callback URL is returned in the `callbackUrl` field of the API JSON response (or `callback_url` in the Python SDK). If this is not done, the 3LO authorization flow will fail with a redirect URI mismatch error from the OAuth2 provider. **Always remind the user of this step when setting up OAuth2 for 3LO.**

**SDK**:
```python
from greennode_agentbase.identity import CreateOauth2ProviderRequest

provider = await client.create_oauth2_provider_async(
    request=CreateOauth2ProviderRequest(
        name="google-oauth",
        client_id="xxx.apps.googleusercontent.com",
        client_secret="GOCSPX-xxx",
        authorization_url="https://accounts.google.com/o/oauth2/v2/auth",
        token_url="https://oauth2.googleapis.com/token",
    )
)
print(f"Created: {provider.name} (callback: {provider.callback_url})")
```

**CLI**:
```bash
bash .claude/skills/agentbase/scripts/auth.sh oauth2 create --name google-oauth \
  --client-id "xxx.apps.googleusercontent.com" \
  --client-secret-env GOOGLE_CLIENT_SECRET \
  --authorization-url "https://accounts.google.com/o/oauth2/v2/auth" \
  --token-url "https://oauth2.googleapis.com/token"
```

### auth oauth2 list
- **Query params**: `page` (0-indexed), `size`, `sortBy`, `sortDirection`

**SDK**:
```python
result = await client.list_oauth2_providers_async(page=0, size=20)
for p in result.content:
    print(f"{p.name} (status: {p.status}, callback: {p.callback_url})")
```

**CLI**:
```bash
bash .claude/skills/agentbase/scripts/auth.sh oauth2 list
```

### auth oauth2 get [name]

**SDK**:
```python
provider = await client.get_oauth2_provider_async(name="google-oauth")
print(f"Name: {provider.name}")
print(f"Client ID: {provider.client_id}")
print(f"Authorization URL: {provider.authorization_url}")
print(f"Token URL: {provider.token_url}")
print(f"Callback URL: {provider.callback_url}")
print(f"Status: {provider.status}")
```

**CLI**:
```bash
bash .claude/skills/agentbase/scripts/auth.sh oauth2 get --name google-oauth
```

### auth oauth2 update [name]
Update an existing OAuth2 provider configuration. **All fields are required** — you must provide all four values even if only changing one.

- **Body**: `{"clientId": "...", "clientSecret": "...", "authorizationUrl": "...", "tokenUrl": "..."}`
- All fields are required: `clientId` (1-100 chars), `clientSecret` (1-100 chars), `authorizationUrl` (0-1000 chars), `tokenUrl` (0-1000 chars)

**SDK**:
```python
from greennode_agentbase.identity import UpdateOauth2ProviderRequest

provider = await client.update_oauth2_provider_async(
    name="google-oauth",
    request=UpdateOauth2ProviderRequest(
        client_id="new-xxx.apps.googleusercontent.com",
        client_secret="GOCSPX-new-xxx",
        authorization_url="https://accounts.google.com/o/oauth2/v2/auth",
        token_url="https://oauth2.googleapis.com/token",
    )
)
print(f"Updated: {provider.name}")
```

**CLI**:
```bash
bash .claude/skills/agentbase/scripts/auth.sh oauth2 update --name google-oauth \
  --client-id "new-xxx.apps.googleusercontent.com" \
  --client-secret-env GOOGLE_CLIENT_SECRET \
  --authorization-url "https://accounts.google.com/o/oauth2/v2/auth" \
  --token-url "https://oauth2.googleapis.com/token"
```

### auth oauth2 delete [name]

**Before deleting**: Consider exporting or noting the resource configuration, as deletion is irreversible. There is no undo.

- Confirm with user before proceeding.

**SDK**:
```python
await client.delete_oauth2_provider_async(name="google-oauth")
```

**CLI**:
```bash
bash .claude/skills/agentbase/scripts/auth.sh oauth2 delete --name google-oauth
```

### auth oauth2 m2m-token [providerName] [agentIdentityName]
Get a machine-to-machine (M2M) OAuth2 token using client credentials flow. For full API details, SDK examples, and decorator usage (`@requires_access_token`), see `references/usage.md`.

**CLI**:
```bash
bash .claude/skills/agentbase/scripts/auth.sh oauth2 get-m2m-token --provider google-oauth --identity my-agent --scopes "scope1,scope2"
```

### auth oauth2 3lo-token [providerName] [agentIdentityName]
Get a 3-legged OAuth (3LO) token via user authorization flow. For full API details, SDK examples, and decorator usage (`@requires_access_token`), see `references/usage.md`.

**CLI**:
```bash
bash .claude/skills/agentbase/scripts/auth.sh oauth2 get-3lo-token --provider google-oauth --identity my-agent --agent-user-id user123 --return-url "https://example.com/callback" --scopes "scope1,scope2"
```

- `customState` (string, optional, max 100 chars) -- custom state to pass through the OAuth2 authorization flow

> **IMPORTANT**: The `returnUrl` parameter **must be included in the `allowedReturnUrls` list** of the agent identity being used. If the URL is not whitelisted in the agent identity, the API will reject the request. Use `/agentbase-identity` to add the URL to the identity's `allowedReturnUrls` if needed.

---

## Auth Prerequisites

Auth operations that retrieve keys or tokens (e.g., `auth apikey retrieve-key`, `auth delegated request-key`, `auth oauth2 m2m-token`, `auth oauth2 3lo-token`) require an **agent identity name**. On AgentBase Runtime, this is automatically managed and injected by the runtime system. For local development, if the user hasn't created one yet, guide them to create an agent identity first using `/agentbase-identity` before proceeding with these operations.

## Credential Rotation

For detailed credential rotation guides (API keys, OAuth2, delegated, IAM), see `references/credential-rotation.md`.
