---
name: agentbase-policy
description: "Author authorization policies for GreenNode AgentBase resources. Covers Policy Groups, Policies, and the policy `statement` body — effect (allow/deny), principal (jwt/iam), actions, resources, and the 9 condition operators on context.*, context.input.*, principal.* keys. Today the only protected resource type is the Resource Gateway (MCP). DO NOT use for agent code (use /agentbase-wizard), identities (/agentbase-identity), memory (/agentbase-memory), or runtimes (/agentbase-deploy)."
---

# AgentBase Policy Service

Author authorization policies for GreenNode AgentBase resources. A policy decides whether a given caller (identified by `principal`) is allowed to perform a given `action` on a given `resource`, optionally conditioned on attributes of the caller and the request context.

The Policy service is resource-type-agnostic by design — `resources` are written as `<type>:<name>` and `actions` are free-form strings. **Today the only resource type wired into a runtime enforcement point is `gateway` (the Resource Gateway, which evaluates MCP JSON-RPC calls such as `tools/call`)**, but the model is intended to extend to additional resource types over time.

Parse the user's arguments to determine the operation and optional group/policy ID.

## Base URLs

- **Policy**: `https://agentbase.api.vngcloud.vn/policy/api/v1`
- **Operator catalog**: `https://agentbase.api.vngcloud.vn/policy/api/v1/policies/condition-operators`

## Authentication & Endpoints

Read the shared auth setup reference at `/agentbase` skill's `references/auth-setup.md` for full IAM credential configuration. In brief: run `bash .claude/skills/agentbase/scripts/check_credentials.sh iam` to verify credentials are configured, then use `TOKEN=$(bash .claude/skills/agentbase/scripts/get_token.sh)` to obtain a token. **NEVER read `.greennode.json` or `.env` directly** — always use the helper scripts. On 401: re-run with `--force`. If `check_credentials.sh iam` returns MISSING, **STOP — you MUST read** the **"If Credentials Are Not Found"** section in `/agentbase` skill's `references/auth-setup.md` and follow it exactly. Do NOT skip this or provide your own credential setup instructions.

**IMPORTANT:** Before constructing any API URL, read `/agentbase` skill's `references/endpoints.md` for the domain validation whitelist. Only use domains listed there.

---

## Interaction Guidelines

- **Never assume API response structure** — always inspect the actual response before extracting fields. Do not guess field names.
- **Guide first, act only when asked** — if the user asks "how to" author a policy or what an operator means, respond with explanation only. Do NOT execute API calls unless they explicitly ask you to do it for them.
- **Confirm before executing (HARD GATE)** — before any action (create, update, delete), present a clear summary of the operation, the full `statement` JSON (effect / principal / actions / resources / condition), and the target Policy Group, then ask the user to confirm. Do NOT auto-execute. Proceed only when the user responds with an explicit confirmation keyword: `yes`, `confirm`, `ok`, `approve`, `proceed`, `go ahead`, `do it`, `ship it`, `lgtm`, or equivalent affirmative. If the user responds with anything else (parameter changes, questions, corrections), treat it as adjustment input — update the plan and re-present for confirmation. NEVER interpret a non-confirmation response as approval. For destructive operations (delete policy, delete policy group — which cascades and removes all child policies), additionally warn that the action is irreversible.
- **Never auto-decide policy fields** — when authoring a policy, always ask the user for `effect`, `principal`, `actions`, `resources`, and each `condition` clause. You may recommend sensible defaults and show the impact of each choice, but never silently pick.
- **Deny-wins reminder** — when *any* `deny` policy in a group matches a request, the decision is deny. If a user writes a `deny` rule alongside `allow` rules in the same group, surface this so they understand the outcome.
- **Resource-type-specific bypasses** — some resource types short-circuit certain actions regardless of policy. For `gateway` today, the Resource Gateway always permits the MCP discovery method `tools/list`. If a user expects to block a "list/discovery"-style action with a policy, check the resource type's behaviour first and say so.
- **Dry-run support**: when user requests `--dry-run` or preview, show the exact API request (method, URL, headers, payload) and explain the expected outcome WITHOUT executing.
- **Always read full API response body** — capture the JSON response (not just status). On 400 the server returns a precise error such as `operator "is" is not supported; see GET /api/v1/policy/condition-operators` — surface that text to the user verbatim instead of paraphrasing.

---

# Core Concepts

| Concept | Description | Quota |
|---|---|---|
| **Policy Group** | Top-level container of policies, identified by `policyGroupId`. The enforcement point (today: the Resource Gateway) evaluates one group per request. | Max **20 per user** |
| **Policy** | Single authorization rule belonging to a group. The rule body lives under the `statement` field. | Max **10 per group** |
| **`statement`** | The rule body: `effect`, `principal`, `actions`, `resources`, `condition`. Sent as the `statement` field on create/update. | — |
| **Effect** | `allow` or `deny`. **Lowercase only.** When any matching `deny` exists in the group, the decision is deny. | — |
| **Principal** | Caller scope: `*` (any), `jwt:*`, `iam:*`, `jwt:<id>`, `iam:<id>`. Only `jwt` and `iam` types are recognised. | — |
| **Actions** | List of actions the rule applies to. `["*"]` or specific entries matching `target__method` (alphanumeric + underscore, with `__` as the separator). The Policy service validates the *format* generically; the **meaning of `target__method` is set by the resource type**. For `gateway` today, `target` is the MCP server target name on the gateway and `method` is the tool name in `tools/call` (e.g. `hr__lookup_employee` matches `tools/call` to target `hr`, tool `lookup_employee`). Other resource types will define their own action vocabulary. | ≥1 |
| **Resources** | List of `<type>:<name>` entries (e.g. `gateway:hr-prod`), or `<type>:*`, or the universal `*`. Wildcard cannot be mixed with specific entries. The only resource type recognised today is `gateway`. | ≥1 |
| **Condition** | Map of `<operator>` → `{ <key>: <value> }`. Multiple operators AND together; multiple keys inside one operator AND together. Omit for unconditional rules. | optional |

> **Resource-type-specific behaviour.** Each resource type can short-circuit certain actions. For `gateway` today, `tools/list` is always allowed regardless of policies. New resource types may have their own bypasses — when in doubt, check the resource type's documentation.

## Supported Condition Operators (the only nine)

| Operator | Arity | Value type | Example |
|---|---|---|---|
| `equals` | single | string / long / bool | `{"equals": {"principal.role": "analyst"}}` |
| `notEquals` | single | string / long / bool | `{"notEquals": {"principal.status": "suspended"}}` |
| `in` | list | string[] | `{"in": {"context.ip": ["203.0.113.10", "203.0.113.11"]}}` |
| `like` | single | string (glob `*`) | `{"like": {"principal.role": "admin-*"}}` |
| `contains` | single | string | `{"contains": {"principal.email": "@vng.com.vn"}}` |
| `lessThan` | single | long | `{"lessThan": {"context.input.qty": 100}}` |
| `lessThanOrEqual` | single | long | `{"lessThanOrEqual": {"context.input.qty": 100}}` |
| `greaterThan` | single | long | `{"greaterThan": {"context.input.qty": 0}}` |
| `greaterThanOrEqual` | single | long | `{"greaterThanOrEqual": {"context.input.qty": 1}}` |

Any other operator name is rejected by the API (HTTP 400) with a pointer to the operator catalog. Live source of truth: `GET /policy/api/v1/policies/condition-operators`.

## Condition Keys

Each key is `<prefix>.<identifier>` (single identifier, letters/digits/underscore, not starting with a digit; no nested paths). The API accepts three prefixes at create/update time — `context.<name>`, `context.input.<name>`, `principal.<name>` — but **only the specific keys below are populated by the enforcement point today**. Any other key in those namespaces is syntactically valid but will never match at decision time, so the rule effectively never fires.

For the `gateway` resource type, the keys populated today are:

| Key | Source | Notes |
|---|---|---|
| `context.ip` | Client IP of the inbound request. | Always populated. |
| `context.input.<name>` | Subfield `<name>` of `params.arguments` in the MCP JSON-RPC body. | Only present for actions that carry a `params.arguments` object (in practice, `tools/call`). Referencing a subfield the caller did not send produces a `TYPE_MISMATCH` deny — not a silent miss. |
| `principal.<name>` | A claim from the caller's JWT. | **JWT inbound auth only.** When the gateway is fronted by other inbound auth methods (e.g. IAM), there are no JWT claims to match against, so a condition on `principal.*` will never be satisfied. If a user wants per-IAM-user rules, identify them via the `principal: "iam:<id>"` header instead. |

`principal.id` is reserved (caller identity belongs in the policy's `principal` field, not in a condition) and `resource.*` keys are not supported.

## Operations Summary

### Policy Groups

| Operation | Method | Endpoint |
|---|---|---|
| Create | `POST` | `/policy-groups` |
| List | `GET` | `/policy-groups?page=1&page_size=10&name=...` |
| Get | `GET` | `/policy-groups/{group_id}` |
| Update | `PUT` | `/policy-groups/{group_id}` |
| Delete (cascade) | `DELETE` | `/policy-groups/{group_id}` |

### Policies (nested under a group)

| Operation | Method | Endpoint |
|---|---|---|
| Create | `POST` | `/policy-groups/{group_id}/policies` |
| List | `GET` | `/policy-groups/{group_id}/policies?page=1&page_size=10&name=...` |
| Get | `GET` | `/policy-groups/{group_id}/policies/{policy_id}` |
| Update | `PUT` | `/policy-groups/{group_id}/policies/{policy_id}` |
| Delete | `DELETE` | `/policy-groups/{group_id}/policies/{policy_id}` |

### Operator catalog

| Operation | Method | Endpoint |
|---|---|---|
| List supported operators | `GET` | `/policies/condition-operators` (sends `Accept-Language: en\|vi` for localized display names) |

**Pagination**: Policy service uses **1-indexed** pagination with the GreenNode-style response shape (`listData`, `totalItem`, `totalPage`, `page`, `pageSize`). Defaults: `page=1`, `page_size=10`, max `page_size=100`.

Read `references/policy-statement.md` for full `statement` authoring rules. Read `references/policy-ops.md` for curl recipes for every endpoint. Read `references/examples.md` for end-to-end realistic policy examples.

## Top-Level Instructions

1. Parse the user's argument to determine the operation (`group` or `policy`, plus `create | list | get | update | delete`) and any name/ID provided.
2. If credentials are not configured, follow the credential setup flow in `/agentbase` skill's `references/auth-setup.md` — do not invent your own.
3. Before building a request, confirm the **Policy Group ID** the policy belongs to. If unknown, list groups first (`GET /policy-groups`) and let the user pick.
4. For **create / update**: collect each `statement` field individually — `effect`, `principal`, `actions`, `resources`, and each `condition` clause. Validate locally against the rules in `references/policy-statement.md` before sending; this surfaces problems faster than a round trip.
5. For **delete policy group**: warn that deletion cascades to all child policies and is irreversible.
6. After any **create / update / delete**, fetch the affected resource(s) again so the user sees the persisted state, not your assumption.
7. Show curl examples by default (this skill is for platform management, not in-agent code). If the user is scripting from Python, use `requests` with the same payload shape.

---

# Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `operator "X" is not supported` | Used an operator outside the supported set. | Use one of the 9 supported operators. `GET /policies/condition-operators` is the live source of truth. |
| `unknown operator "X"` | Typo or unsupported operator name. | Check the operator catalog. Operator names are case-sensitive camelCase. |
| `invalid condition key "X"` | Key does not match `context.<name>`, `context.input.<name>`, or `principal.<name>` (single identifier, no nested paths). | Use one of the allowed prefixes with a single identifier. |
| `invalid effect "X": must be 'allow' or 'deny'` | Used `Allow` / `Deny` / `permit` / `forbid`. | Lowercase `allow` or `deny` only. |
| `invalid action entry "X": must be '*' or match targetname__methodname` | Used `/`, space, dash, or other unsupported characters in an action. | Use `*` or `target__method` (alphanumeric + underscore, with `__` between target and method). |
| `wildcard resource cannot be mixed with specific entries` | Mixed `*` (or `gateway:*`) with `gateway:foo`. | Use either wildcard alone or only specific entries. |
| 401 Unauthorized | Expired or invalid IAM token | Re-obtain token with `bash .claude/skills/agentbase/scripts/get_token.sh --force`. Confirm `GREENNODE_CLIENT_ID` / `GREENNODE_CLIENT_SECRET` are correct. |
| 403 Forbidden | Service account lacks Policy service permissions | Check IAM roles at https://iam.console.vngcloud.vn |
| 404 Not Found on policy | Policy ID does not exist in the given group | Verify with `GET /policy-groups/{group_id}/policies` |
| 409 Conflict | Group or policy name already exists for this portal user / group | Pick a different name |
| 429 Too Many Requests | Exceeded quota (20 groups/user or 10 policies/group) | Delete unused entries or consolidate |
