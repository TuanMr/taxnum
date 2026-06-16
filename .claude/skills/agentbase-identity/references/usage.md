# AgentBase Auth — Advanced Operations & Decorator Usage

## Advanced Operations

### delegated request-key [providerName] [agentIdentityName]
Request a delegated API key (triggers user-federation flow).

- **API**: `POST /api/v1/outbound-auth/delegated-api-key-providers/{providerName}/agent-identities/{agentIdentityName}/api-key`
- **Body fields**:
  - `agentUserId` (string, **required**, minLength 1) — unique identifier of the end-user
  - `returnUrl` (string, **required**, 0-1000 chars) — must be in the agent identity's `allowedReturnUrls`
  - `customState` (string, optional, 1-100 chars) — custom state passed through the delegation flow
  - `sessionId` (string, optional, UUID) — resume a previous delegation session
  - `forceDelegation` (boolean, optional) — force re-delegation even if a key already exists

> **IMPORTANT**: The `returnUrl` value **must be listed in the `allowedReturnUrls`** of the agent identity being used. If not, the API will reject the request. Update the agent identity via `/agentbase-identity` to add the URL first.

**SDK**:
```python
from greennode_agentbase.identity import GetDelegatedApiKeyRequest

result = await client.get_delegated_api_key_for_agent_identity_async(
    provider_name="user-openai-key",
    agent_identity_name="my-agent",
    request=GetDelegatedApiKeyRequest(
        agent_user_id="user-123",
        return_url="https://myapp.com/callback",
    ),
)
# result.apikey - the key if already authorized
# result.authorization_url - URL to redirect user for consent
# result.status - IN_PROGRESS, COMPLETED, or FAILED
```

### oauth2 m2m-token [providerName] [agentIdentityName]
Get a machine-to-machine (M2M) OAuth2 token using client credentials flow.

- **API**: `POST /api/v1/outbound-auth/oauth2-providers/{providerName}/agent-identities/{agentIdentityName}/tokens/m2m`
- **Body fields**:
  - `scopes` (array of strings, **required**, minItems 1, unique items) — OAuth2 scopes to request

**SDK**:
```python
from greennode_agentbase.identity import GetM2mTokenRequest

result = await client.get_m2m_token_async(
    provider_name="google-oauth",
    agent_identity_name="my-agent",
    request=GetM2mTokenRequest(scopes=["https://www.googleapis.com/auth/calendar.readonly"]),
)
print(f"Access Token: {result.access_token}")
print(f"Token Type: {result.token_type}")
```

### oauth2 3lo-token [providerName] [agentIdentityName]
Get a 3-legged OAuth (3LO) token via user authorization flow.

- **API**: `POST /api/v1/outbound-auth/oauth2-providers/{providerName}/agent-identities/{agentIdentityName}/tokens/3lo`
- **Body fields**:
  - `agentUserId` (string, **required**, minLength 1) — unique identifier of the end-user
  - `scopes` (array of strings, **required**, minItems 1, unique) — OAuth2 scopes to request
  - `returnUrl` (string, **required**, 0-1000 chars) — must be in the agent identity's `allowedReturnUrls`
  - `sessionId` (string, optional, UUID) — resume a previous authorization session
  - `customParameters` (object, optional) — additional key-value parameters passed to the authorization URL
  - `customState` (string, optional, 1-100 chars) — custom state passed through the OAuth2 flow
  - `forceAuthentication` (boolean, optional) — force re-authentication even if a token already exists

> **IMPORTANT**: The `returnUrl` value **must be listed in the `allowedReturnUrls`** of the agent identity being used. If not, the API will reject the request. Update the agent identity via `/agentbase-identity` to add the URL first.

**SDK**:
```python
from greennode_agentbase.identity import ThreeLoTokenRequest

result = await client.get_3lo_token_async(
    provider_name="google-oauth",
    agent_identity_name="my-agent",
    request=ThreeLoTokenRequest(
        agent_user_id="user-123",
        scopes=["openid", "email"],
        return_url="https://myapp.com/callback",
    ),
)
# result.access_token - if user already authorized
# result.authorization_url - if user needs to authorize (redirect user here)
# result.session_id - for polling until authorization completes
# result.status - IN_PROGRESS, COMPLETED, or FAILED
```

---

## Decorator Usage Examples

## Static API Key (`@requires_api_key` with M2M flow)

```python
from greennode_agentbase import requires_api_key

@requires_api_key(provider_name="openai-key", auth_flow="M2M")
def call_openai(api_key: str):
    # api_key is automatically injected from the stored provider
    client = openai.OpenAI(api_key=api_key)
    return client.chat.completions.create(...)
```

## Delegated API Key (`@requires_api_key` with USER_FEDERATION flow)

```python
from greennode_agentbase import requires_api_key

@requires_api_key(
    provider_name="user-openai-key",
    auth_flow="USER_FEDERATION",
    callback_url="https://myapp.com/callback",
    on_auth_url=lambda url: print(f"Please authorize: {url}"),
)
async def call_openai(api_key: str):
    # api_key is automatically injected after user completes delegation
    client = openai.OpenAI(api_key=api_key)
    return client.chat.completions.create(...)
```

## OAuth2 M2M Token (`@requires_access_token` with M2M flow)

```python
from greennode_agentbase import requires_access_token

@requires_access_token(
    provider_name="google-oauth",
    scopes=["https://www.googleapis.com/auth/calendar.readonly"],
    auth_flow="M2M",
)
async def read_calendar(access_token: str):
    # access_token is automatically injected via client credentials flow
    pass
```

## OAuth2 3LO Token (`@requires_access_token` with USER_FEDERATION flow)

```python
from greennode_agentbase import requires_access_token

@requires_access_token(
    provider_name="google-oauth",
    scopes=["openid", "email"],
    auth_flow="USER_FEDERATION",
    callback_url="https://myapp.com/callback",
    on_auth_url=lambda url: print(f"Please authorize: {url}"),
)
async def get_user_info(access_token: str):
    # access_token injected after user completes OAuth consent
    pass
```
