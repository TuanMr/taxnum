# `outboundAuth` — How the Gateway Authenticates to Targets

Every `target` registered on a gateway carries its own `outboundAuth` block. When the gateway forwards an MCP JSON-RPC call to that target, it attaches the credentials configured here. Secrets are **never** embedded in the gateway spec — both `APIKEY` and `OAUTH` reference a credential pre-registered in AgentBase Identity by `providerName`. A third type, `NONE`, attaches no credential at all.

```json
{
  "type":              "NONE | APIKEY | OAUTH",
  "flow":              "2LO | 3LO",
  "headerName":        "string",
  "headerValuePrefix": "string",
  "providerName":      "string",
  "scopes":            ["string"],
  "returnUrl":         "https://...",
  "customParameters":  { "key": "value" }
}
```

Only `type` is unconditionally required. `flow` is required **when `type` is `APIKEY` or `OAUTH`** (and is not used for `NONE`). The remaining fields are required-conditional on `type` and `flow`. Unused fields are stripped server-side, so it's safe to send them as empty/null but cleaner to omit them.

**Matrix of allowed combinations:**

| `type` | `flow` | Meaning |
|---|---|---|
| `NONE`   | — | No outbound credential attached. |
| `APIKEY` | `2LO` | Gateway-level static API key, shared across all callers. |
| `APIKEY` | `3LO` | Per-end-user API key — resolved per caller via Identity. |
| `OAUTH`  | `2LO` | OAuth 2.0 client-credentials (machine-to-machine). |
| `OAUTH`  | `3LO` | OAuth 2.0 authorization-code with end-user consent. |

---

## Type: `NONE`

```json
{ "outboundAuth": { "type": "NONE" } }
```

The gateway forwards the MCP call to the target without attaching any credential. No `flow`, `providerName`, or header fields are needed (they are ignored if sent). Use for upstream MCP servers that are open, or that authenticate by network position / IP allow-list rather than by a token the gateway must supply — e.g. a PRIVATE-network target reachable only from inside the VPC.

---

## Type: `APIKEY`

The gateway injects an API key under `headerName` on every upstream request. The **actual key value** is stored in AgentBase Identity, keyed by `providerName` — confirm via `/agentbase-identity` that the provider exists before pointing a target at it. The gateway looks up the secret at call time and constructs the header value as `<headerValuePrefix><secret>`.

| Field | Required? | Notes |
|---|---|---|
| `flow` | Yes | `2LO` for a single shared key; `3LO` for per-caller keys (see flow sections below). |
| `headerName` | Yes | The HTTP header to set on the outbound request, e.g. `X-Api-Key`, `Authorization`, `X-Custom-Token`. Do not include the colon. |
| `headerValuePrefix` | Yes (may be empty) | Prepended to the secret. Use `"Bearer "` (trailing space) when the upstream expects `Authorization: Bearer <key>`. Use `""` for plain header value. |
| `providerName` | Yes | Identifier the gateway uses to look up the API key in AgentBase Identity. Must match a provider already registered via `/agentbase-identity`. |

**Common header shapes:**

| Upstream expects | `headerName` | `headerValuePrefix` |
|---|---|---|
| `X-Api-Key: <key>` | `X-Api-Key` | `""` |
| `Authorization: Bearer <key>` | `Authorization` | `"Bearer "` |
| `Authorization: Token <key>` | `Authorization` | `"Token "` |

### Flow: `APIKEY` + `2LO` (shared key)

```json
{
  "outboundAuth": {
    "type":              "APIKEY",
    "flow":              "2LO",
    "headerName":        "X-Api-Key",
    "headerValuePrefix": "",
    "providerName":      "hr-mcp-apikey"
  }
}
```

A single API key is resolved from Identity and reused for every call into this target, regardless of which caller hit the gateway. Use for service-account-style upstream auth.

### Flow: `APIKEY` + `3LO` (per-user key)

```json
{
  "outboundAuth": {
    "type":              "APIKEY",
    "flow":              "3LO",
    "headerName":        "Authorization",
    "headerValuePrefix": "Bearer ",
    "providerName":      "github-pat"
  }
}
```

The gateway looks up an API key **per calling principal** in Identity under the same `providerName`. Use when each end user needs their own upstream credential (personal access tokens, per-user webhooks, etc.). Requires an inbound auth mode that produces a stable principal — `IAM` or `JWT` — so Identity can scope the lookup.

---

## Type: `OAUTH`

OAuth 2.0 outbound auth. The gateway fetches an access token from the upstream's IdP and attaches it as `Authorization: Bearer <access_token>` to the forwarded request.

```json
{
  "outboundAuth": {
    "type":         "OAUTH",
    "flow":         "2LO | 3LO",
    "providerName": "string",
    "scopes":       ["string"],
    "returnUrl":    "https://callback.example.com/oauth/return",
    "customParameters": { "tenant": "acme" }
  }
}
```

| Field | Required for | Notes |
|---|---|---|
| `flow` | both | `2LO` for client-credentials (machine-to-machine); `3LO` for authorization-code with a human consent step. |
| `providerName` | both | The identity provider registration name in AgentBase Identity. Holds `client_id`, `client_secret`, and (for 3LO) the authorize/token endpoints. |
| `scopes` | both | Space-separated scope list the gateway requests from the IdP. |
| `returnUrl` | `3LO` only | Redirect URI registered with the IdP. The 3LO consent flow returns here after the user approves. Must be HTTPS. |
| `customParameters` | `3LO` only (optional) | Free-form key/value map forwarded verbatim to the identity service when resolving the OAUTH+3LO secret. Useful for tenants, audience overrides, organization IDs, etc. **Stripped for `2LO`** and for non-OAUTH types. |

### Flow: `OAUTH` + `2LO` (client credentials)

```json
{
  "outboundAuth": {
    "type":         "OAUTH",
    "flow":         "2LO",
    "providerName": "okta-machine",
    "scopes":       ["mcp.invoke"]
  }
}
```

Pure machine-to-machine. The gateway exchanges its registered `client_id` / `client_secret` for an access token at the IdP's token endpoint, caches it for its TTL, then attaches it to each upstream call. No user interaction.

### Flow: `OAUTH` + `3LO` (authorization code with consent)

```json
{
  "outboundAuth": {
    "type":         "OAUTH",
    "flow":         "3LO",
    "providerName": "google-workspace",
    "scopes":       ["https://www.googleapis.com/auth/calendar.readonly"],
    "returnUrl":    "https://hr-prod-<hash>.gateway.agentbase.vngcloud.vn/oauth/return",
    "customParameters": { "prompt": "consent" }
  }
}
```

End-user consent required. The first time the gateway needs a token for a given caller, it redirects the caller through the IdP authorize endpoint to `returnUrl`. Subsequent calls use the cached refresh token. `customParameters` are appended to the authorize request (e.g. `prompt=consent`, `access_type=offline`, `tenant=<id>`).

> **Provider registration order matters.** The gateway resolves `providerName` against AgentBase Identity **at call time**, not at create time, so a typo in `providerName` will not block `POST /gateways`. It will fail later as a 502 from the upstream MCP call. Verify via `/agentbase-identity` that the provider exists with the exact name before pointing a target at it.

---

## Choosing per target

| Upstream auth scheme | `type` | `flow` |
|---|---|---|
| Upstream needs no credential (open, or IP/network-gated) | `NONE` | — |
| Static API key shared by all callers (`X-Api-Key`, `Authorization: Bearer …`) | `APIKEY` | `2LO` |
| Per-user API key / personal access token | `APIKEY` | `3LO` |
| Machine-to-machine OAuth (no end-user) | `OAUTH` | `2LO` |
| End-user OAuth (Google, Microsoft 365, Slack, Notion, …) | `OAUTH` | `3LO` |

Mixing within one gateway is fine — every target picks its own scheme. The gateway evaluates `outboundAuth` per-call and rotates secrets independently per `providerName`.

## Replacing the targets list

PATCH on `targets` is a **full replacement**, not a diff:

```jsonc
// Goal: keep "hr", add "payroll", drop "old-staging".
// Send the full desired list:
{
  "targets": [
    { "name": "hr",      "type": "MCP", "endpoint": "...", "outboundAuth": { "type": "APIKEY", "flow": "2LO", "headerName": "X-Api-Key", "headerValuePrefix": "", "providerName": "hr-apikey" } },
    { "name": "payroll", "type": "MCP", "endpoint": "...", "outboundAuth": { "type": "APIKEY", "flow": "2LO", "headerName": "X-Api-Key", "headerValuePrefix": "", "providerName": "payroll-apikey" } }
  ]
}
```

To clear every target, send `"targets": []`. **Never send `null`** — the API rejects it.

## Common mistakes

| Mistake | Symptom |
|---|---|
| Missing `flow` on `APIKEY` or `OAUTH` | 400 validation error. `flow` is required whenever `type` is `APIKEY` or `OAUTH` (only `type=NONE` omits it). |
| `headerName: "Authorization:"` (trailing colon) | 400 validation error. Drop the colon. |
| `APIKEY` with no `providerName` (or named provider not registered in Identity) | 502 from upstream at first call. Register the provider via `/agentbase-identity` and re-PATCH the target. |
| `APIKEY` + `3LO` behind an inbound auth of `NONE` | No stable principal → Identity can't pick a per-user key. Switch inbound to `IAM` or `JWT`. |
| `OAUTH 3LO` with a non-HTTPS `returnUrl` | 400 validation error. The redirect URI must be HTTPS. |
| `OAUTH 2LO` with `customParameters` | Silently stripped — `customParameters` only flows through for `3LO`. |
| Sending `Bearer <key>` literal as `headerValuePrefix + secret` where the prefix already includes `Bearer ` **and** the registered secret also starts with `Bearer ` | Double prefix arrives upstream. Either keep `Bearer ` in the prefix and register a bare key, or register `Bearer <key>` as the secret and leave the prefix empty — never both. |
