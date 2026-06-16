# Policy Examples

Realistic, runnable policy `statement` examples — one per common scenario. Drop each `statement` block into `POST /policy-groups/{group_id}/policies` (see `policy-ops.md`).

Every example below uses **only condition keys that the gateway actually populates today** — `context.ip`, `context.input.<name>`, and `principal.<name>` (JWT claims). A policy referencing some other `context.<name>` (e.g. `context.env`, `context.hour`) will save successfully but the condition will never match at decision time.

---

## 1. Allow active HR analysts; deny suspended (JWT claims)

```json
{
  "name": "hr-analyst-active",
  "description": "Allow active HR analysts to invoke tools",
  "statement": {
    "effect": "allow",
    "principal": "jwt:*",
    "actions": ["*"],
    "resources": ["*"],
    "condition": {
      "equals":    { "principal.department": "HR",
                     "principal.role":       "analyst" },
      "notEquals": { "principal.status": "suspended" }
    }
  }
}
```

**Allows** a JWT caller whose token carries `department=HR`, `role=analyst`, and `status` != `suspended`. **Blocks** non-HR users, non-analysts, suspended analysts, and any IAM caller (no JWT claims to match).

**Note:** `principal.*` references read JWT claims. This rule only fires when inbound auth is JWT. Scope the rule explicitly with `principal: "jwt:*"` so its intent is obvious and IAM traffic falls through to other rules.

---

## 2. IP allowlist via `context.ip`

```json
{
  "name": "office-network-only",
  "description": "Allow only callers from approved office IPs",
  "statement": {
    "effect": "allow",
    "principal": "*",
    "actions": ["*"],
    "resources": ["*"],
    "condition": {
      "in": { "context.ip": ["203.0.113.10", "203.0.113.11", "198.51.100.7"] }
    }
  }
}
```

**Allows** requests whose client IP is one of the three listed. **Blocks** every other origin (no permit applies). `context.ip` is the client IP the gateway observes for the inbound request.

> The `in` operator does exact string equality, not CIDR matching. List each address explicitly.

---

## 3. Wildcard JWT role (`like`)

```json
{
  "name": "any-admin-prefix",
  "description": "Any admin-* role can call any tool — JWT users only",
  "statement": {
    "effect": "allow",
    "principal": "jwt:*",
    "actions": ["*"],
    "resources": ["*"],
    "condition": {
      "like": { "principal.role": "admin-*" }
    }
  }
}
```

**Allows** JWT users with `role` like `admin-billing`, `admin-ops`, etc. **Blocks** JWT users without an `admin-` role and IAM users (no JWT claims).

---

## 4. Deny-wins — block a specific IP regardless of other allows

```json
[
  {
    "name": "permit-jwt-analysts",
    "statement": {
      "effect": "allow",
      "principal": "jwt:*",
      "actions": ["*"],
      "resources": ["*"],
      "condition": {
        "equals": { "principal.role": "analyst" }
      }
    }
  },
  {
    "name": "deny-quarantined-ip",
    "statement": {
      "effect": "deny",
      "principal": "*",
      "actions": ["*"],
      "resources": ["*"],
      "condition": {
        "equals": { "context.ip": "192.0.2.55" }
      }
    }
  }
]
```

Two policies in the same group. **Allows** JWT analysts from any IP except `192.0.2.55`. **Blocks** that one IP outright — even for users the first rule would otherwise permit, because deny wins.

---

## 5. Per-principal-type — JWT broad, IAM scoped by ID

```json
[
  {
    "name": "jwt-broad",
    "statement": {
      "effect": "allow",
      "principal": "jwt:*",
      "actions": ["*"],
      "resources": ["*"]
    }
  },
  {
    "name": "iam-named-service-accounts",
    "statement": {
      "effect": "allow",
      "principal": "iam:reporting-bot",
      "actions": ["*"],
      "resources": ["*"]
    }
  }
]
```

**Allows** every JWT call and IAM calls made by the `reporting-bot` service account specifically. **Blocks** every other IAM caller (no permit applies). IAM-side scoping has to live in the `principal` header because IAM principals do not carry JWT claims for conditions to read.

---

## 6. Department membership via `in` (JWT)

```json
{
  "name": "allowed-departments",
  "statement": {
    "effect": "allow",
    "principal": "jwt:*",
    "actions": ["*"],
    "resources": ["*"],
    "condition": {
      "in": { "principal.department": ["HR", "Finance", "Engineering", "Legal"] }
    }
  }
}
```

**Allows** JWT callers whose `department` claim is one of the four listed. **Blocks** other departments and any IAM caller.

---

## 7. JSON-RPC argument validation via `context.input`

```json
{
  "name": "vn-region-low-volume-only",
  "description": "Only allow tools/call when arguments.region == 'vn' and arguments.qty <= 100",
  "statement": {
    "effect": "allow",
    "principal": "*",
    "actions": ["*"],
    "resources": ["*"],
    "condition": {
      "equals":          { "context.input.region": "vn" },
      "lessThanOrEqual": { "context.input.qty":    100 }
    }
  }
}
```

`context.input.<name>` reads subfields of `params.arguments` in the MCP JSON-RPC body, so the policy gates on tool-call arguments directly.

**Allows** a `tools/call` with `params.arguments = { "region": "vn", "qty": 50 }`. **Blocks** `region: "us"` (gateway response reason code `NO_PERMIT`) or `qty: 500`. If the caller omits `qty` the call is denied with reason code `TYPE_MISMATCH`.

> `context.input.*` is only populated when the action carries a `params.arguments` object — i.e. `tools/call`. Bare methods like `tools/list` have no input to check (and are universally allowed anyway).

---

## 8. Scope to specific gateway targets

```json
{
  "name": "hr-prod-only",
  "statement": {
    "effect": "allow",
    "principal": "jwt:*",
    "actions": ["*"],
    "resources": ["gateway:hr-prod", "gateway:hr-staging"]
  }
}
```

**Allows** JWT calls to either named gateway. **Blocks** calls to any other gateway target (no permit applies). Resource entries cannot mix `*` with specific names.

---

## 9. Per-action — specific tool only (gateway)

```json
{
  "name": "lookup-employee-only",
  "statement": {
    "effect": "allow",
    "principal": "*",
    "actions": ["hr__lookup_employee"],
    "resources": ["gateway:hr-prod"]
  }
}
```

**Allows** exactly the `hr__lookup_employee` action on `hr-prod`. For the `gateway` resource type, this maps to a `tools/call` whose JSON-RPC `params` selects target `hr` and tool `lookup_employee`. **Blocks** any other tool, including other tools on the same gateway. `tools/list` is still permitted by the universal bypass.

> The Policy service enforces the `target__method` *format* (alphanumeric + underscore, with `__` as the separator) for every statement, but the `target` and `method` themselves are defined by the resource type's enforcement point. Today that means the gateway's MCP target/tool naming — there is no other resource type that reads these action names yet.

---

## Anti-patterns (don't author these)

```json
// Capitalised effect — REJECTED at create
{ "effect": "Allow", ... }

// Nested condition key — REJECTED at create
{ "condition": { "equals": { "principal.profile.email": "x@y" } } }

// principal.id in a condition — REJECTED at create (put it in the header)
{ "condition": { "equals": { "principal.id": "alice" } } }

// Rejected operator — REJECTED at create with a pointer to the operator catalog
{ "condition": { "ipInRange": { "context.ip": "10.0.0.0/8" } } }

// Wildcard mixed with specific resource — REJECTED at create
{ "resources": ["*", "gateway:hr-prod"] }
```

```json
// Saves cleanly, but the condition never matches at decision time because
// the gateway does not populate context.env / context.hour today.
// The rule effectively does nothing — this is the most common source of
// "my policy isn't being enforced" reports.
{
  "condition": {
    "equals":   { "context.env":  "prod" },
    "lessThan": { "context.hour": 17 }
  }
}
```

```json
// principal.* conditions paired with an IAM principal — IAM callers
// do not carry JWT claims, so this rule never permits anyone.
{
  "principal": "iam:*",
  "condition": { "equals": { "principal.role": "analyst" } }
}
```
