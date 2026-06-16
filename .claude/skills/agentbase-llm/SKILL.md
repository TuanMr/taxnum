---
name: agentbase-llm
description: "Manage platform LLM model access and API keys for AI agents. Use when user wants to set up LLM access, get a platform API key, browse available models, choose which LLM to use, configure model access, check rate limits, or get an OpenAI-compatible endpoint. Trigger for which models are available, set up LLM, API key for the model, list models, LLM key, connect to LLM. When user says API key without specifying an external service name, default to this skill. DO NOT use for storing API keys for external services (OpenAI, Google, Slack) — use /agentbase-identity instead."
---

# GreenNode AI Platform — API Keys & LLM Models

Manage API keys and browse LLM models on the GreenNode AI Platform (MAAS). API keys created here are OpenAI-compatible and can be used with the LLM endpoint to power AI agents.

**LLM Endpoint (OpenAI-compatible):** `https://maas-llm-aiplatform-hcm.api.vngcloud.vn/v1`

Use `bash .claude/skills/agentbase/scripts/aip.sh help` for full command reference.

## Authentication

Read the shared auth setup reference at `/agentbase` skill's `references/auth-setup.md` for full IAM credential configuration. In brief: run `bash .claude/skills/agentbase/scripts/check_credentials.sh iam` to verify credentials are configured, then use `TOKEN=$(bash .claude/skills/agentbase/scripts/get_token.sh)` to obtain a token. **NEVER read `.greennode.json` or `.env` directly** — always use the helper scripts. On 401: re-run with `--force`. If `check_credentials.sh iam` returns MISSING, **STOP — you MUST read** the **"If Credentials Are Not Found"** section in `/agentbase` skill's `references/auth-setup.md` and follow it exactly. Do NOT skip this or provide your own credential setup instructions.

## Interaction Guidelines

- **Never assume API response structure** — always inspect the actual response first before extracting or filtering data. Do not guess field names.
- **Guide first, act only when asked** — if the user asks "how to" manage API keys or browse models, respond with instructions and guidance only. Do NOT execute API calls or create resources unless they explicitly ask you to do it for them.
- **Confirm before executing (HARD GATE)** — before performing any mutating action (create, delete, enable/disable model), present a clear summary of what will be done (including all parameters and values) and ask the user to confirm. Read-only operations (list, get, metadata, rate-limit) proceed directly without confirmation. Do NOT auto-execute. Only proceed when the user responds with an explicit confirmation keyword: `yes`, `confirm`, `ok`, `approve`, `proceed`, `go ahead`, `do it`, `ship it`, `lgtm`, or equivalent affirmative. If the user responds with ANYTHING ELSE (parameter changes, questions, corrections, additional info, or ambiguous text), treat it as adjustment input — update the plan and re-present the full summary for confirmation again. NEVER interpret a non-confirmation response as approval. For destructive operations (delete API key), additionally warn that the action is irreversible.
- **Never auto-decide parameters** — when an action requires parameters (e.g., API key name, model UUID), always ask the user for each required value. You may recommend sensible defaults or examples, but never auto-select or impose values without the user's explicit agreement.
- **Present options, let user choose** — when there are multiple choices (e.g., existing API keys, available models), list the available options and let the user pick. Do not make the choice for them.
- **Dry-run support**: When user requests `--dry-run` or preview, show the exact command and API request that would be sent (method, URL, payload) and explain the expected outcome WITHOUT executing. The scripts do not support a `--dry-run` flag — construct the preview manually. Let user review before proceeding.
- **Always read full API response body** — when calling platform APIs, capture and read the full JSON response (not just status codes). This avoids misidentifying field names or data structures, ensures correct field extraction, and enables better error handling and debugging.

---

## API Key Management

API keys grant access to LLM models through the OpenAI-compatible endpoint. Once you have a key, you can use it like an OpenAI API key.

### api-keys list
List all API keys for the current account.

```bash
bash .claude/skills/agentbase/scripts/aip.sh api-keys list [--name NAME] [--page N] [--size N]
```

**Note**: AI Platform uses 1-indexed pagination (page=1 is first page).

Response contains a paginated list with fields: `listData` (array of keys), `page`, `pageSize`, `totalPage`, `totalItem`. Each key has: `id`, `name`, `key`, `status`, `isDefault`, `models`, `createdAt`.

### api-keys create [name]
Create a new API key. The script sends the request, saves the key to `.env`, and returns immediately. You must poll `api-keys get <name>` until status is `ACTIVE`.

- **Name constraints:** 5-50 chars, pattern `^[a-z0-9\-]{5,50}$` (lowercase letters, digits, hyphens only)

```bash
bash .claude/skills/agentbase/scripts/aip.sh api-keys create --name my-agent-key [--default]
```

**If creation fails with a quota error** (e.g. 400/409 indicating quota exhausted), do NOT auto-retry. Instead:
1. List all existing API keys using `aip.sh api-keys list`.
2. Present the list to the user and explain that their API key quota is full.
3. Suggest the user **delete an unused key** to free up quota. Ask which key they want to delete.
4. After the user confirms deletion, delete the key. Note: deletion is **async** — you must poll `aip.sh api-keys list --name <name>` every 5-10 seconds until no key with that **exact** name remains in `listData` (the `--name` filter matches substrings, so verify the exact name is gone, not just that the list is non-empty). Wait for deletion to complete before proceeding. If it doesn't complete within 2-3 minutes, inform the user that the operation is taking longer than expected.
5. Retry creating the new key **once**. If creation fails again, inform the user that the issue is not quota-related and ask them to check their account status or billing. Do NOT loop — max 1 retry after a deletion.

After creating a key, remind the user:
> Your API key can be used as an OpenAI-compatible key:
> - **Base URL:** `https://maas-llm-aiplatform-hcm.api.vngcloud.vn/v1`
> - **API Key:** saved to `.env` as `LLM_API_KEY`. Verify with `bash .claude/skills/agentbase/scripts/check_credentials.sh llm`

### api-keys get [name]
Get details of a specific API key. The `key` field is redacted in stdout by design — the plaintext key is never printed.

```bash
bash .claude/skills/agentbase/scripts/aip.sh api-keys get my-agent-key
```

To **load an existing key into `.env`** (e.g. when reusing a key instead of creating one), add `--save-env`. The key is written to `.env` as `LLM_API_KEY` silently — it never appears in output:

```bash
bash .claude/skills/agentbase/scripts/aip.sh api-keys get my-agent-key --save-env
# then verify: bash .claude/skills/agentbase/scripts/check_credentials.sh llm
```

### api-keys update [name]
Update an API key (currently supports setting default status).

```bash
bash .claude/skills/agentbase/scripts/aip.sh api-keys update my-agent-key --default true
```

### api-keys delete [name]
Delete an API key. Confirm with the user before proceeding. The script sends the DELETE request and returns immediately. You must confirm deletion by polling `api-keys list --name <name>` until no entry with that exact name remains in `listData`.

```bash
bash .claude/skills/agentbase/scripts/aip.sh api-keys delete my-agent-key
```

Note: a key can only be deleted once it is `ACTIVE` — deleting a `CREATING` key fails, and a per-account lock rejects concurrent deletes (`400 "User is already deleting API keys."`).

Confirm deletion to the user only after the key no longer appears in `api-keys list`. Do NOT confirm immediately after the script returns — deletion is async.

---

## LLM Model Management

Browse, inspect, and enable/disable available LLM models. These models are accessible via the OpenAI-compatible endpoint using an API key from above.

### models list
List available models with optional filters.

```bash
# List all models
bash .claude/skills/agentbase/scripts/aip.sh models list

# Filter by provider and type
bash .claude/skills/agentbase/scripts/aip.sh models list --providers openai --types chat --status ENABLED
```

> **Tip**: Use `bash .claude/skills/agentbase/scripts/aip.sh models metadata` to discover valid filter values for `--providers`, `--types`, and `--status`.

Response contains: `listData` (array of models), `page`, `pageSize`, `totalPage`, `totalItem`. Key fields in each model: `uuid`, `name`, `code`, `path`, `description`, `modelStatus`, `isFree`, `provider`, `types`.

### models get [modelUuid]
Get detailed information about a specific model.

```bash
bash .claude/skills/agentbase/scripts/aip.sh models get MODEL_UUID
```

### models metadata
Get available filter options (providers, types, use cases) for model listing.

```bash
bash .claude/skills/agentbase/scripts/aip.sh models metadata
```

This is useful to discover what providers, model types, and use cases are available before filtering the model list.

### models enable [modelUuid]
Enable an LLM model for your account.

```bash
bash .claude/skills/agentbase/scripts/aip.sh models enable MODEL_UUID
```

After enabling, verify by fetching the model detail and checking `isEnabled == true`. The enable operation is synchronous — verify immediately after the call returns.

**Billing errors:** If the enable request fails with a billing-related error (e.g. 400/402/403 indicating unpaid balance, insufficient credits, or billing not activated), do NOT retry. Instead:
1. Inform the user that the operation failed due to a billing issue.
2. Explain that they need to check and resolve their billing status before enabling the model.
3. Direct them to the GreenNode AI Platform console at https://aiplatform.console.vngcloud.vn/models to review their account and billing status.
4. Once billing is resolved, they can retry enabling the model.

### models disable [modelUuid]
Disable an LLM model for your account.

```bash
bash .claude/skills/agentbase/scripts/aip.sh models disable MODEL_UUID
```

### models rate-limit [modelUuid]
Check rate limit configuration for a specific model.

```bash
bash .claude/skills/agentbase/scripts/aip.sh models rate-limit MODEL_UUID
```

---

## Using with OpenAI SDK

Once you have an API key, you can use GreenNode LLM models with any OpenAI-compatible client:

```python
from openai import OpenAI

client = OpenAI(
    api_key="YOUR_GREENNODE_API_KEY",
    base_url="https://maas-llm-aiplatform-hcm.api.vngcloud.vn/v1",
)

response = client.chat.completions.create(
    model="MODEL_PATH",  # use the `path` field from model detail (not `code`). If `path` is missing, use `code`.
    messages=[{"role": "user", "content": "Hello!"}],
)
print(response.choices[0].message.content)
```

```typescript
import OpenAI from "openai";

const client = new OpenAI({
  apiKey: "YOUR_GREENNODE_API_KEY",
  baseURL: "https://maas-llm-aiplatform-hcm.api.vngcloud.vn/v1",
});

const response = await client.chat.completions.create({
  model: "MODEL_PATH",  // use the `path` field from model detail (not `code`). If `path` is missing, use `code`.
  messages: [{ role: "user", content: "Hello!" }],
});
```

---

## Troubleshooting

| Error | Cause | Fix |
|-------|-------|-----|
| 401 Unauthorized | Expired or invalid IAM token | Re-obtain token with valid `client_id`/`client_secret` |
| 403 Forbidden | Service account lacks permissions | Check IAM permissions at GreenNode IAM console https://iam.console.vngcloud.vn |
| 404 Not Found | API key name or model UUID not found | Verify with a `list` operation |
| 409 Conflict | API key name already exists | Choose a different name |
| Invalid name | Name doesn't match `^[a-z0-9\-]{5,50}$` | Use only lowercase letters, digits, and hyphens (5-50 chars). Note: this pattern differs from Identity service which allows uppercase and underscores (`^[a-zA-Z0-9_-]+$`, 3-50 chars) |
| 400/402/403 on model enable | Billing issue (unpaid balance, no credits, billing not activated) | Check and resolve billing at https://aiplatform.console.vngcloud.vn/models before retrying |

## Instructions

1. Parse the user's request to determine the resource type (`api-keys` or `models`) and operation.
2. If unclear, ask the user what they need:
   - **api-keys**: "I want to create/manage API keys for accessing LLM models"
   - **models**: "I want to see what LLM models are available and their details"
3. **When the user needs an API key, always let the user decide:**
   - First, list existing API keys using `aip.sh api-keys list`.
   - Present the existing keys to the user (if any) and explicitly ask them to choose one of the following options:
     - **Use an existing key** — let the user pick which one from the list
     - **Create a new key** — proceed to create a new API key
   - Do NOT auto-select or auto-use any existing key. The user must explicitly choose.
   - If the user is unsure which key to use, list all keys with their names and status, and recommend the one marked `isDefault: true`. If the user says "use any" or "just pick one", use the default key.
   - **Once the user picks an existing key, load it into `.env`** by running `aip.sh api-keys get <name> --save-env`. Reusing a key without this step leaves `LLM_API_KEY` unset — the key is only auto-saved on create, so an existing key must be captured explicitly. Confirm with `check_credentials.sh llm`.
4. **When creating a new API key fails with a quota error:**
   - Do NOT retry the creation. Explain that the API key quota is full.
   - List all existing API keys and present them to the user.
   - Guide the user to **delete an unused key** to free up quota. Ask which key they want to delete.
   - After deletion completes, retry creating the new key.
5. For `api-keys create`, ask for the key name if not provided. Validate it matches `^[a-z0-9\-]{5,50}$`.
6. **api-keys create is async**: the script POSTs to the v2 endpoint, which returns `200` with the plaintext key in the response (initial `status: CREATING`). The script saves the key to `.env` immediately and returns. You must then poll the status by calling `aip.sh api-keys get <name>` every 5-10 seconds until the `status` field is `ACTIVE`. The key is already in `.env` from the create step — do NOT re-run `--save-env` here, it is redundant. The plaintext key is redacted from all output by design — never expect to see it; confirm it landed with `check_credentials.sh llm`.
7. **api-keys delete is async**: the script sends the DELETE request and returns immediately. You must then poll by calling `aip.sh api-keys list --name <name>` every 5-10 seconds until no key with that **exact** name remains in `listData` (the `--name` filter is a substring match — confirm the exact name is absent). Only confirm deletion to the user after the key is gone. Note: a key must be `ACTIVE` to be deleted, and concurrent deletes are rejected with `400 "User is already deleting API keys."`.
8. After creating an API key, show the OpenAI-compatible usage info: the **base URL** and that the key is stored in `.env` as `LLM_API_KEY` (verify with `check_credentials.sh llm`). Never print the plaintext key — it is redacted from all command output by design.
9. When listing or showing model details, highlight the model `path` field — this is what must be passed as the `model` parameter when calling the LLM API (not `code`; if `path` is missing, fall back to `code`). Do NOT show pricing/billing info (`inputPrice`, `outputPrice`) to the user — pricing may be subject to negotiated contracts; refer users to the billing dashboard instead.
10. When the user wants to set up LLM access for an agent, guide them through: (1) browse models to pick one, (2) list existing API keys and reuse one, or create a new key if needed, (3) use the key with the OpenAI SDK pointing to the GreenNode endpoint.
11. **When the user needs to pick a model**, list available models filtered by `status=ENABLED` and sorted by most recent first, then **let the user choose**. Do not auto-select or recommend a specific model unless the user explicitly asks for a recommendation.
12. **When enabling a model** via `aip.sh models enable`, if the request fails with a billing-related error (400/402/403 with messages about billing, credits, or payment), do NOT retry. Inform the user that the operation failed due to a billing issue and that they need to check and resolve their billing status at https://aiplatform.console.vngcloud.vn/models before retrying. Do not attempt workarounds — billing issues must be resolved by the user.
