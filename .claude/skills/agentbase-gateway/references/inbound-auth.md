# `inboundAuth` — How the Gateway Authenticates Callers

The `inboundAuth` block decides how the gateway authenticates the **caller** (agent, script, or end user) hitting its endpoint. Per-target authentication to the upstream MCP server is configured separately in each target's `outboundAuth` — see `outbound-auth.md`.

```json
{
  "mode": "NONE | IAM | JWT",
  "jwt":  { /* required when mode=JWT only; see below */ }
}
```

PATCH replaces `inboundAuth` wholesale (Merge Patch does not deep-merge nested config). When switching modes, send the **full new block** — e.g. switching `JWT → IAM` means `{ "mode": "IAM" }` with `jwt` omitted.

---

## Mode: `NONE`

```json
{ "inboundAuth": { "mode": "NONE" } }
```

No authentication. **Any caller** that can reach the gateway endpoint can invoke targets. The bound Policy Group (if any) still runs, but `principal.*` JWT claims are unavailable, so policies relying on `principal.*` will never match.

Reserve `NONE` for internal lab gateways or for cases where authentication is enforced one hop upstream (e.g. a private network with mutual TLS at the edge).

---

## Mode: `IAM`

```json
{ "inboundAuth": { "mode": "IAM" } }
```

The gateway accepts a VNG Cloud IAM bearer token in the standard `Authorization: Bearer <token>` header. The caller's IAM identity becomes `iam:<id>` for policy purposes. IAM mode requires **no additional configuration** — there are no allowed-clients, allowed-audiences, or claim rules in this mode.

When to use:
- Service-to-service calls within the same VNG Cloud tenant.
- Agents deployed via `/agentbase-deploy` (the runtime auto-injects IAM credentials).
- Per-user rules expressed by `principal: "iam:<id>"` in `/agentbase-policy`.

Limitation: there are no JWT claims to match against, so `principal.<name>` conditions in policies will **never** be satisfied for IAM traffic — use `principal: "iam:<id>"` or `iam:*` instead.

---

## Mode: `JWT`

```json
{
  "inboundAuth": {
    "mode": "JWT",
    "jwt": {
      "source":           "DISCOVERY",
      "discoveryUrl":     "https://issuer.example.com/.well-known/openid-configuration",
      "principalClaim":   "sub",
      "allowedAudiences": ["hr-prod-gateway"],
      "allowedClients":   ["client-id-1", "client-id-2"],
      "allowedScopes":    ["mcp.read", "mcp.write"],
      "customClaims": [
        { "key": "email", "operator": "<see-issuer-docs>", "values": ["@vng.com.vn"] }
      ]
    }
  }
}
```

The gateway verifies the caller's JWT and exposes its claims as `principal.<name>` to the policy engine.

### `source` (required)

| Value | Meaning |
|---|---|
| `DISCOVERY` | Fetch the signing keys via the issuer's OIDC discovery document. Supply `discoveryUrl` (e.g. `https://issuer.example.com/.well-known/openid-configuration`). The gateway caches the JWKS the document points at and refreshes it periodically. |
| `JWKS` | Pin the signing keys yourself. Supply a static `jwks` object (a JSON Web Key Set). Use this when the issuer does not publish a discovery endpoint, or when you need to lock to a specific key rotation. |

Pick **one**. Sending both `discoveryUrl` and `jwks` is rejected.

### `principalClaim` (optional)

Which claim identifies the caller. Defaults to `sub`. The matched value becomes the `<id>` portion of `jwt:<id>` for `/agentbase-policy` `principal:` matching.

### `allowedAudiences[]` (optional)

Restrict accepted tokens by `aud`. If non-empty, the token's `aud` claim must contain at least one entry from this list. Leave empty to skip the audience check.

### `allowedClients[]` (optional)

Restrict accepted tokens by `azp` / `client_id`. If non-empty, the token's authorized-party claim must be in this list. Useful when the same issuer serves many clients and you only want one or two to reach this gateway.

### `allowedScopes[]` (optional)

Restrict by `scope` (space-delimited string per RFC 8693). If non-empty, the token must include **all** listed scopes (logical AND). Leave empty to skip the scope check.

### `customClaims[]` (optional, advanced)

Free-form claim rules evaluated after the standard checks. Each rule is:

```json
{ "key": "<claim_name>", "operator": "<operator>", "values": ["..."] }
```

The Gateway service stores these rules opaquely and applies them at JWT validation time. The public schema does **not** enumerate the supported `operator` names — they depend on the gateway version. Do **not** copy operator strings from this document or from policy docs without verifying; treat the `<see-issuer-docs>` placeholder as a reminder to ask the platform team or test against a real token first. When in doubt:

1. Start with no `customClaims` and prove the gateway works on the bare token first.
2. Add one rule at a time, testing with a real token from your IdP.
3. Move conditional logic that depends on claim values into `/agentbase-policy` rather than `customClaims`. Policy rules are richer (9 supported operators, full deny-wins semantics) and easier to reason about.

> **Two-layer enforcement.** `customClaims` and `allowedScopes` are *admission checks* — the gateway rejects the request entirely if they fail. Policy rules are *authorization checks* — they decide whether a particular `target__method` action is permitted. Reach for policies first; only use `customClaims` to keep traffic out of the gateway before it even reaches the policy engine.

### Worked configurations

**Public OIDC issuer (Okta / Auth0 / Cognito):**
```json
{
  "mode": "JWT",
  "jwt": {
    "source":           "DISCOVERY",
    "discoveryUrl":     "https://dev-12345.okta.com/.well-known/openid-configuration",
    "principalClaim":   "sub",
    "allowedAudiences": ["api://hr-prod"],
    "allowedScopes":    ["mcp.invoke"]
  }
}
```

**Self-hosted issuer with static JWKS (no discovery):**
```json
{
  "mode": "JWT",
  "jwt": {
    "source": "JWKS",
    "jwks": {
      "keys": [
        { "kty": "RSA", "kid": "2026-q2", "use": "sig", "alg": "RS256",
          "n": "0vx...", "e": "AQAB" }
      ]
    },
    "principalClaim": "sub"
  }
}
```

**Locked to a specific client and domain:**
```json
{
  "mode": "JWT",
  "jwt": {
    "source":           "DISCOVERY",
    "discoveryUrl":     "https://login.example.com/.well-known/openid-configuration",
    "allowedClients":   ["abc123"],
    "customClaims": [
      { "key": "email", "operator": "<see-issuer-docs>", "values": ["@vng.com.vn"] }
    ]
  }
}
```

---

## Choosing a mode

| Scenario | Mode |
|---|---|
| Agents deployed via `/agentbase-deploy` calling each other | `IAM` |
| External SaaS or browser front-end hitting MCP | `JWT` (DISCOVERY) |
| Air-gapped or internal-only proxy | `NONE` (with network-level isolation) |
| Mixed IAM + end-user JWT traffic | Pick one mode per gateway — run two gateways pointing at the same upstreams if you need both. |

## How `inboundAuth` interacts with policy

The bound Policy Group decides authorization **after** inbound auth succeeds. The available context per mode:

| Mode | Policy context |
|---|---|
| `NONE` | `context.ip` only. `principal: "*"` matches; any `principal.*` condition will never fire. |
| `IAM` | `context.ip`, plus `principal: "iam:<id>"`. `principal.*` conditions never fire (no JWT claims). |
| `JWT` | `context.ip`, plus `principal: "jwt:<id>"` and `principal.<claim>` keys from the token. |

See `/agentbase-policy` `references/policy-statement.md` for the full set of supported policy operators and key prefixes.
