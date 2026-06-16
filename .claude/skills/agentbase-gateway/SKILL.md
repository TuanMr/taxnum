---
name: agentbase-gateway
description: "Manage GreenNode AgentBase Resource Gateway (MCP) — a managed proxy in front of user MCP servers with inbound auth, per-target outbound auth, and policy enforcement. Trigger: create/list/update/delete a gateway, register an MCP target, configure inbound auth (NONE/IAM/JWT) or per-target outbound auth (APIKEY/OAUTH, each with 2LO or 3LO flow), change VPC routes, bind a Policy Group. DO NOT use for agent runtimes (/agentbase-deploy) or for authoring policy rules (/agentbase-policy)."
---

# AgentBase Resource Gateway

Manage the **Resource Gateway** — a managed proxy that sits in front of one or more user MCP servers (the **targets**) and adds inbound authentication, optional policy enforcement, and per-target outbound authentication. Callers (agents, scripts, or users) hit the gateway endpoint; the gateway authenticates the caller, evaluates the bound Policy Group, swaps in the target's outbound credential, and forwards the MCP JSON-RPC call upstream.

- **Console**: https://aiplatform.console.vngcloud.vn/mcp-gateway

Parse the user's arguments to determine the operation (`create | list | get | update | delete | routes | repair | flavors`) and any name they provide.

## Base URL

`https://agentbase.api.vngcloud.vn/gateway/api/v1`

## Authentication & Endpoints

Read the shared auth setup reference at `/agentbase` skill's `references/auth-setup.md` for full IAM credential configuration. In brief: run `bash .claude/skills/agentbase/scripts/check_credentials.sh iam` to verify credentials are configured, then `TOKEN=$(bash .claude/skills/agentbase/scripts/get_token.sh)` to obtain a token. **NEVER read `.greennode.json` or `.env` directly** — always use the helper scripts. On 401: re-run with `--force`. If `check_credentials.sh iam` returns MISSING, **STOP — you MUST read** the **"If Credentials Are Not Found"** section in `/agentbase` skill's `references/auth-setup.md` and follow it exactly. Do NOT skip this or provide your own credential setup instructions.

**IMPORTANT:** Before constructing any API URL, read `/agentbase` skill's `references/endpoints.md` for the domain validation whitelist. Only use domains listed there.

---

## Interaction Guidelines

- **Never assume API response structure** — always inspect the actual response before extracting fields. Do not guess field names.
- **Guide first, act only when asked** — if the user asks "how to" create a gateway, register a target, or configure auth, respond with explanation only. Do NOT execute API calls unless they explicitly ask you to do it for them.
- **Confirm before executing (HARD GATE)** — before any action (create, update, delete, routes update, repair), present a clear summary of the operation, the full request payload (with secrets redacted), the target gateway name, the chosen `networkMode`, `inboundAuth`, the list of `targets` with their outbound auth, and any `policyGroupId` binding. Ask the user to confirm. Do NOT auto-execute. Proceed only when the user responds with an explicit confirmation keyword: `yes`, `confirm`, `ok`, `approve`, `proceed`, `go ahead`, `do it`, `ship it`, `lgtm`, or equivalent affirmative. If the user responds with anything else (parameter changes, questions, corrections), treat it as adjustment input — update the plan and re-present for confirmation. NEVER interpret a non-confirmation response as approval. For destructive operations (delete gateway, replace targets list, replace routes), additionally warn that the action is irreversible / disruptive.
- **Never auto-decide gateway fields** — always ask the user for `name`, `networkMode`, `flavorId`, `replicas`, `inboundAuth.mode`, each target's `endpoint` + `outboundAuth.type`, and any `policyGroupId`. You may recommend sensible defaults and explain trade-offs, but never silently pick.
- **Sealed fields cannot be patched** — `name`, `networkMode`, `privateNetwork.vpcId`, `privateNetwork.subnetId`, `flavorId`, `replicas`. Changing any of these requires deleting and recreating the gateway. Warn the user up front.
- **PATCH uses JSON Merge Patch semantics** (RFC 7396). `null` clears a field; **omitting** a field leaves it untouched. For `inboundAuth`, send the **full replacement** object (not a partial merge); for `targets`, send the **entire desired array** (or `[]` to clear) — never `null`.
- **Optimistic concurrency** — every mutable response carries an `ETag` header containing the current `resourceVersion`. Pass it back as `If-Match` on the next PATCH / PUT to detect concurrent edits. Even without `If-Match` the server CAS-checks on the stored version, so retries on **412 Precondition Failed** are expected — re-`GET` to fetch the fresh version, rebase the change, and retry.
- **Async transitions** — `POST`, `PATCH`, `DELETE`, and routes `PUT` typically return **202 Accepted** with the gateway in a `*ING` state. Poll `GET /gateways/{name}` until `state` is `ACTIVE` (or a terminal error state) before declaring success. The PATCH/PUT path may also return **200 OK** when the change is metadata-only and no rollout is needed.
- **Secret hygiene** — bot tokens, OAuth client secrets, JWKS keys, and similar values are stored upstream via AgentBase Identity (`/agentbase-identity`) by `providerName`, not embedded in the gateway. Never ask the user to paste raw secrets into the conversation. For OAUTH outbound auth you collect the `providerName` only; the secret lives in Identity.
- **Dry-run support** — when the user requests `--dry-run` or preview, show the exact API request (method, URL, headers, payload) and explain the expected outcome WITHOUT executing.
- **Always read full API response body** — capture the JSON response (not just status). On 400 the server returns a precise error such as `name: must match ^[a-z0-9-]{3,40}$` — surface that text to the user verbatim instead of paraphrasing.

---

# Core Concepts

| Concept | Description |
|---|---|
| **Gateway** | The managed proxy. Identified by `name` (sealed, 3–40 chars, `^[a-z0-9-]+$`, no leading/trailing dash). Exposes a single `endpoint` URL that speaks MCP JSON-RPC. |
| **Network mode** | `PUBLIC` (reachable on the internet) or `PRIVATE` (joined to a VNG Cloud VPC subnet). Sealed; requires recreate to change. PRIVATE additionally requires `vpcId`, `subnetId`, and optional `routes` (≤50 private IPv4 CIDRs). |
| **Flavor** | Compute size. Listed via `GET /flavors?resourceType=GATEWAY`. For PRIVATE add `networkMode=PRIVATE&zoneId=<uuid>`. Sealed on create. |
| **Replicas** | 1–10. Sealed on create. |
| **Inbound auth** | How the gateway authenticates the **caller**. `NONE`, `IAM` (VNG Cloud IAM bearer), or `JWT` (OIDC discovery or static JWKS, with optional `principalClaim`, `allowedAudiences`, `allowedClients`, `allowedScopes`, and `customClaims` rules). Replaceable via PATCH. |
| **Target** | An upstream MCP server registered on the gateway. Each target has a `name` (3–50, `^[a-z0-9-]+$`), `type` (today `MCP`), an `endpoint` (`https://…`, ≤1000 chars), and an `outboundAuth` block. The full `targets` array is replaceable via PATCH (≤ operator-configured `gateway.maxTargets`, default 50 — exceeding returns 422). |
| **Outbound auth** | How the gateway authenticates **to the upstream target**. Three types — `NONE` (no credential attached), `APIKEY`, and `OAUTH`; `APIKEY`/`OAUTH` each take `flow=2LO` (shared/machine-to-machine) or `flow=3LO` (per-end-user), while `NONE` takes no `flow`. The secret value (the API key string, or the OAuth `client_id`/`client_secret`) is never embedded in the gateway spec. Instead, the user first stores the secret in the AgentBase Identity service via `/agentbase-identity`, giving it a name (`providerName`). The gateway spec carries only this `providerName`; at call time the gateway looks up the secret from Identity by that name. |
| **Policy Group binding** | Optional `policyGroupId` linking the gateway to a Policy Group authored via `/agentbase-policy`. When bound, every MCP `tools/call` invocation is evaluated against that group; `tools/list` is always allowed regardless of policy. |
| **State** | `WAITING_CREATING` → `CREATING` → `ACTIVE`; `UPDATING`; `WAITING_DELETING` → `DELETING`; plus error states (`ERROR`, `UPDATE_ERROR`, …). PATCH on a transient state may fail with 409. |
| **Service account** | The gateway runs under an internal IAM service account (`iam.serviceAccountId`). If it gets accidentally reset/disabled, `POST /gateways/{name}/service-account/repair` rebuilds it. |

> **Action vocabulary** (for `/agentbase-policy`): the gateway evaluates MCP actions in the form `target__method` — e.g. a `tools/call` to target `hr`, tool `lookup_employee` becomes `hr__lookup_employee`. `tools/list` is exempt from policy evaluation. See `/agentbase-policy` for full policy authoring.

## Operations Summary

| Operation | Method | Endpoint |
|---|---|---|
| List flavors | `GET` | `/flavors?resourceType=GATEWAY[&networkMode=PRIVATE&zoneId=<uuid>]` |
| List gateways | `GET` | `/gateways?page=1&pageSize=50[&state=…&policyGroupId=…]` |
| Create gateway | `POST` | `/gateways` |
| Get gateway | `GET` | `/gateways/{name}` |
| Update gateway (JSON Merge Patch) | `PATCH` | `/gateways/{name}` |
| Delete gateway | `DELETE` | `/gateways/{name}` |
| Get routes (PRIVATE only) | `GET` | `/gateways/{name}/private-network/routes` |
| Replace routes (PRIVATE only) | `PUT` | `/gateways/{name}/private-network/routes` |
| Repair service account | `POST` | `/gateways/{name}/service-account/repair` |

**Pagination** (list gateways): `page` (default 1), `pageSize` (default 50, max 200). Response: `{ items: [...], pagination: { page, pageSize, totalItems, hasMore } }`.

Read **`references/gateway-ops.md`** for full curl recipes for every endpoint (request bodies, response shapes, error codes, ETag/If-Match handling).
Read **`references/inbound-auth.md`** for `inboundAuth` modes and JWT configuration rules.
Read **`references/outbound-auth.md`** for `outboundAuth` configuration per auth type.
Read **`references/examples.md`** for end-to-end realistic scenarios (PUBLIC + JWT + APIKEY target, PRIVATE/VPC + OAuth 3LO target with policy binding, route updates, SA recovery).

---

## Top-Level Instructions

1. Parse the user's argument to determine the operation (`create | list | get | update | delete | routes | repair | flavors`) and any gateway name they supplied.
2. If credentials are not configured, follow the credential setup flow in `/agentbase` skill's `references/auth-setup.md` — do not invent your own.
3. For **create**:
   - Ask for `name`, `networkMode`, and `replicas` first (sealed — they cannot be changed later).
   - For `PRIVATE`, run vServer discovery to look up `vpcId` / `subnetId` (see `/agentbase-deploy` Part 1 for the same scripts: `vserver.sh projects` → `vpcs` → `subnets` → `validate-vpc`). Do not ask the user to guess UUIDs.
   - Call `GET /flavors?resourceType=GATEWAY` (add `networkMode=PRIVATE&zoneId=<uuid>` for PRIVATE) and present the list; let the user pick. **Never auto-select.**
   - Collect `inboundAuth` interactively (see `references/inbound-auth.md`).
   - Collect each target's `name`, `endpoint`, and `outboundAuth` (see `references/outbound-auth.md`). If a target uses `OAUTH`, confirm the corresponding `providerName` is already registered via `/agentbase-identity` — the gateway create will fail at first call otherwise.
   - Optionally bind a `policyGroupId` (must already exist — list via `/agentbase-policy`).
   - Show the full payload, get confirmation, POST, then poll `GET` until `state=ACTIVE`. Surface the `endpoint` URL once active.
4. For **update**: GET the gateway first to capture the current ETag (`resourceVersion`). Build a JSON Merge Patch with only the user-mutable fields the user wants to change (`displayName`, `description`, `policyGroupId`, `inboundAuth`, `targets`). Re-confirm any sealed-field requests with a delete-and-recreate plan. Send PATCH with `If-Match: "<resourceVersion>"`. On 412, GET again, rebase, and re-confirm.
5. For **delete**: warn that deletion is irreversible, that any agents pointing at this gateway's endpoint will start failing, and that downstream Policy Group bindings remain (delete those separately via `/agentbase-policy` if no longer needed).
6. For **routes** (PRIVATE only): GET current routes, present them, ask the user for the new list (or "add X" / "remove Y" intent — you compute the resulting full list), and `PUT` the complete replacement array. Routes must be private IPv4 CIDRs (≤50 entries).
7. For **repair**: only call when the user reports auth failures originating from the gateway's IAM service account, or when the get-gateway response shows `iam.lastAuthFailureAt` is set. Confirm before posting — repair triggers a brief rollout.
8. After any **create / update / delete / routes / repair**, GET the gateway again so the user sees the persisted state, not your assumption.
9. Show curl examples by default. If the user is scripting from Python, use `requests` with the same payload shape.

---

# Troubleshooting

| Symptom / Error | Likely cause | Fix |
|---|---|---|
| 400 `name: must match ^[a-z0-9-]{3,40}$` | Invalid gateway name (uppercase, underscore, dash at edge, too short/long). | Use 3–40 lowercase letters / digits / dashes, no leading/trailing dash. |
| 400 `privateNetwork is required when networkMode=PRIVATE` | PRIVATE mode without `vpcId` / `subnetId`. | Supply both. Discover via `vserver.sh`. |
| 400 invalid CIDR / non-IPv4 / public range | Route entry isn't a private IPv4 CIDR. | Use RFC 1918 ranges only; IPv6 and public ranges are rejected. |
| 409 Conflict on create | A gateway with the same `name` already exists for this user. | Choose a different `name`. |
| 412 Precondition Failed | Stale `If-Match` — someone (including a previous async transition) bumped `resourceVersion`. | `GET` the gateway, rebase your patch, retry. Expected on retry loops. |
| 422 quota / no eligible flavor / target cap | User over their gateway quota, no flavor matches the selected `networkMode` + `zoneId`, or `targets.length > gateway.maxTargets`. | Free a slot, pick a different flavor, or split into multiple gateways. |
| State stuck on `CREATING` / `UPDATING` | Backend rollout still in progress, or hitting a transient infra issue. | Poll `GET`. If it transitions to `ERROR` / `UPDATE_ERROR`, inspect `lastError` (stage / code / message). |
| `lastError.stage = applyRoutes`, state `UPDATE_ERROR` | Routes update failed during rollout. | Read the message verbatim; usually a CIDR overlap or VPC peering issue. Retry `PUT /routes` after fixing the input. |
| `iam.lastAuthFailureAt` set, callers hitting 502 | Gateway service account got reset/disabled out-of-band. | `POST /gateways/{name}/service-account/repair`. Brief rollout follows. |
| 502 from upstream MCP call | Target endpoint unreachable, TLS error, or outbound auth misconfigured. | Verify target `endpoint` is reachable from gateway's network mode; check `outboundAuth` (header name, OAuth provider). For PRIVATE gateways, confirm the upstream IP is reachable via the configured `routes`. |
| Policy denies legitimate caller | Bound Policy Group has a `deny` rule matching the caller, or no `allow` matches (deny-by-default). | Review with `/agentbase-policy`. Remember `deny` wins inside a group and `tools/list` is always allowed regardless of policy. |
| 401 Unauthorized | Expired or invalid IAM token. | Re-obtain with `bash .claude/skills/agentbase/scripts/get_token.sh --force`. Confirm `GREENNODE_CLIENT_ID` / `GREENNODE_CLIENT_SECRET`. |
| 403 Forbidden | Service account lacks Gateway service permissions. | Check IAM roles at https://iam.console.vngcloud.vn. |
| 404 Not Found on routes endpoints | Gateway is `PUBLIC` (no routes resource exists) or the name is wrong. | Routes endpoints are PRIVATE-only. Verify `networkMode` via `GET /gateways/{name}`. |
