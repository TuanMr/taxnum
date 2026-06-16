# Policy `statement` Authoring Reference

The `statement` is the rule body sent to the Policy service on create/update (the `statement` field of the create/update request). This file documents every field, the rules each enforces (as observed at the public API), and the gotchas most authors hit first.

## Shape

```json
{
  "effect": "allow",
  "principal": "jwt:*",
  "actions": ["*"],
  "resources": ["gateway:*"],
  "condition": {
    "equals": { "principal.role": "analyst" },
    "in":     { "principal.department": ["HR", "Finance"] }
  }
}
```

`effect`, `principal`, `actions`, `resources` are required. `condition` is optional — omit it for an unconditional rule.

## Fields

### `effect`

- `"allow"` — grants access if the rule matches.
- `"deny"` — blocks access if the rule matches. **Deny wins**: when any matching `deny` exists in the same Policy Group, the decision is deny.

**Lowercase only.** `"Allow"`, `"Deny"`, `"permit"`, `"forbid"` are rejected with HTTP 400.

### `principal`

Identifies who the rule applies to.

| Form | Meaning |
|---|---|
| `"*"` | Any principal, any type. |
| `"jwt:*"` | Any JWT-authenticated user. |
| `"iam:*"` | Any IAM-authenticated user. |
| `"jwt:<id>"` | A single JWT user with the given id. |
| `"iam:<id>"` | A single IAM user with the given id. |

Recognised principal types are **only `jwt` and `iam`**. Any other prefix (`user:`, `service:`, etc.) is rejected.

### `actions`

A non-empty list of action names the policy applies to.

- `["*"]` — every action (subject to per-resource-type bypasses; see below).
- `["target__method"]` — a specific action. Entries must be alphanumeric/underscore, with `__` separating the target part from the method part (e.g. `hr__lookup_employee`). They must start with a letter or digit.
- Multiple specific entries are OR'd: `["billing__lookup_employee", "billing__update_record"]`.

You **cannot** mix `*` with specific entries.

**The `target__method` shape is the action vocabulary used by the `gateway` resource type today.** The Policy service validates the *format* (alphanumeric + underscore, with `__` as the separator) at create/update time for every statement, but the *meaning* of `target` and `method` is defined by the resource type's enforcement point.

For the `gateway` resource type today:
- `target` is the MCP server target name registered on the gateway (the upstream MCP server the gateway routes to).
- `method` is the tool name as it would appear in a `tools/call` request — i.e. the `name` field of `params` in the JSON-RPC body.
- Example: `["hr__lookup_employee"]` matches a `tools/call` to the `hr` target with tool name `lookup_employee`.
- `tools/list` and other discovery methods do not need explicit action entries — `tools/list` is universally allowed by the gateway bypass; other meta methods are not policy-gated either.

When a new resource type is added in the future, it will define its own interpretation of `target` and `method` (and its own bypass list). Until then, if you are writing specific action entries, you are gating MCP tool calls on the gateway — there is no other place these action names are read.

> **Resource-type-specific bypasses.** Each resource type may short-circuit certain actions regardless of policy. For `gateway` today, `tools/list` is always allowed so MCP clients can discover available tools — even an unconditional `deny *` will not block it. If you need to hide tools from discovery, the Policy service is not the right mechanism. New resource types may introduce their own bypasses.

### `resources`

A non-empty list of resources the policy protects.

- `["*"]` — every resource of every type.
- `["<type>:*"]` — every resource of the given type.
- `["<type>:<name>"]` — a single named resource.
- Multiple specific entries are allowed: `["gateway:hr-prod", "gateway:finance-prod"]`.

Wildcard cannot be mixed with specific entries. Each entry must be `type:name` (with non-empty type and name) or `*`.

**Resource types available today:** `gateway` (the Resource Gateway that fronts MCP servers). The `type:name` format leaves room for additional resource types to be added without changing the template shape.

### `condition`

Optional map of `<operator>` → `{ <key>: <value>, ... }`.

- Multiple **operators** in the same condition map are AND'd.
- Multiple **keys** inside one operator are AND'd.
- Each operator appears at most once in the condition map.

## Supported Operators (exactly nine)

`GET /policy/api/v1/policies/condition-operators` is the live source of truth and returns localized display names when `Accept-Language: vi` is sent.

| Name | Arity | Value type(s) | Notes |
|---|---|---|---|
| `equals` | single | string, long, bool | |
| `notEquals` | single | string, long, bool | |
| `in` | list | string[] | Membership in a set. Empty list is rejected. |
| `like` | single | string | Glob — `*` is wildcard. Example: `"admin-*"`. |
| `contains` | single | string | Substring/element containment on the key. |
| `lessThan` | single | long | |
| `lessThanOrEqual` | single | long | |
| `greaterThan` | single | long | |
| `greaterThanOrEqual` | single | long | |

Any other operator returns HTTP 400 with a message pointing at the catalog endpoint. Surface that message to the user directly rather than guessing what is acceptable.

## Condition Keys

Every key is `<prefix>.<identifier>` where `<identifier>` is a single token of letters/digits/underscore not starting with a digit. **No nested paths** — `principal.profile.email` is invalid; `context.foo.bar` is invalid. The bare `context.input` namespace (without a child name) is reserved and cannot be used as a key.

### What the API accepts at create/update

The Policy service validates keys against three prefixes:

- `context.<name>`
- `context.input.<name>`
- `principal.<name>` — reads a JWT claim of that name. `principal.id` is rejected (identity belongs in the policy's `principal` field, not in a condition).

Anything outside these prefixes is rejected with HTTP 400.

`resource.*` keys are not supported. Scope by listing the resource in `resources` instead.

> The internal form `principal.attrs.<name>` is also accepted by the API (the service rewrites the shorthand `principal.<name>` to the internal form at save time), but **prefer the `principal.<name>` form in your statements** — it's the public, documented shape and what every example here uses.

### What the enforcement point actually populates today

The API accepts a broader set of keys than the enforcement point populates. Writing a policy against a key that nobody sets will compile cleanly and pass create — but at decision time the condition never matches, so the rule never fires. This is the most common source of "my policy didn't do anything" reports.

For the `gateway` resource type, the keys populated today are:

| Key | Source | Notes |
|---|---|---|
| `context.ip` | Client IP of the inbound request reaching the gateway. | Always populated. |
| `context.input.<name>` | Subfield `<name>` of `params.arguments` in the MCP JSON-RPC body. | Only present for actions that carry a `params.arguments` object (in practice, `tools/call`). A reference to a subfield the caller omits produces a TYPE_MISMATCH deny, not a silent miss. |
| `principal.<name>` | A claim from the caller's JWT, exposed under its claim name. | **JWT inbound auth only.** When the gateway is fronted by a non-JWT inbound auth method (e.g. IAM), there are no JWT claims to match — a condition on `principal.*` cannot be satisfied. For per-IAM-user rules, identify the caller in the policy's `principal` header instead (`principal: "iam:<id>"` or `principal: "iam:*"`). |

If a future resource type or inbound auth method exposes additional keys, they will appear here without changing the API shape — the three-prefix vocabulary is intentionally open-ended.

## What Makes a Template Valid (in field order)

1. `effect` must be `allow` or `deny`.
2. `principal` must be `*` or `<type>:<id>` with type in `{jwt, iam}`.
3. `actions` must be non-empty; each entry must be `*` or match `target__method`.
4. `resources` must be non-empty; wildcards may not mix with specific entries.
5. Each condition operator must be in the supported catalog.
6. Each condition key must be one of the three allowed prefixes followed by a single identifier; the bare `context.input` namespace is reserved.
7. Operator value types are enforced: `equals/notEquals` accept scalar (string/long/bool); `in` requires a non-empty string list; numeric operators require long; `like`/`contains` require string.

All of these are checked at **create and update** time, so a syntactically invalid template never reaches production. Note that "valid" is weaker than "useful" — see the next section for cases that pass create but never match at decision time.

## Common Gotchas

- **Using `"Allow"` / `"Deny"`.** Lowercase only.
- **Using `has` (or any other unsupported operator) to check attribute presence.** Not supported. If you need "attribute X exists and equals Y", use `equals` directly — when the principal does not supply X the rule simply does not match.
- **Using `principal.id` in a condition.** Rejected. Put the id in `principal: "jwt:<id>"`.
- **Mixing wildcard and specific resources.** Rejected. Either `["gateway:*"]` or `["gateway:a","gateway:b"]`, never both.
- **Forgetting deny-wins.** A permissive `allow *` rule plus a narrower `deny` rule in the same group means the deny wins for any matching request — not "the more specific rule".
- **Trying to enforce an action the resource type bypasses.** Some actions are short-circuited per resource type (e.g. `tools/list` on `gateway`). Policies cannot override these.
- **`context.input.<x>` referenced in a policy, but the request omits `<x>` from the call's input/arguments.** The decision returns a TYPE_MISMATCH reason and the request is denied — it is not silently "no permit applies".
- **Writing a condition on a `context.<name>` that nobody populates.** The API accepts the key syntactically but the gateway never sets a value for it at decision time, so the condition cannot evaluate to true and the rule never fires. Today only `context.ip` and `context.input.<name>` are populated for the `gateway` resource type. This is the most common source of "my policy was saved but has no effect" reports.
- **Pairing `principal.*` conditions with `principal: "iam:*"`.** `principal.*` reads JWT claims; IAM callers do not carry claims. The combination never permits anyone — use the `principal` header (`iam:<id>`) for IAM-side scoping instead.
