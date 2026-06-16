# Policy Service — API Recipes

Curl recipes for every public endpoint. All examples assume:

```bash
BASE=https://agentbase.api.vngcloud.vn/policy/api/v1
TOKEN=$(bash .claude/skills/agentbase/scripts/get_token.sh)
```

Auth header is `Authorization: Bearer $TOKEN`.

Pagination: 1-indexed. Response shape uses GreenNode's `listData` / `totalItem` / `totalPage` / `page` / `pageSize`.

---

## Operator Catalog (live source of truth)

List every operator the API currently accepts, with arity, value types, accepted key prefixes, and a ready-made example. Send `Accept-Language: vi` for Vietnamese display names.

```bash
curl -s "$BASE/policies/condition-operators" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Accept-Language: en" | jq .
```

Response:

```json
{
  "operators": [
    {
      "name": "equals",
      "displayName": "Equals",
      "description": "...",
      "arity": "single",
      "valueTypes": ["string", "long", "bool"],
      "acceptsKeyPrefixes": ["context", "principal", "resource"],
      "example": { "equals": { "context.role": "admin" } }
    }
    // ...
  ]
}
```

`Cache-Control: public, max-age=300` — safe to memoise client-side. If the user asks "what operators are supported?" call this endpoint rather than reciting from memory.

---

## Policy Groups

### Create

```bash
curl -s -X POST "$BASE/policy-groups" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "hr-prod-gateway",
    "description": "Policies guarding the HR production gateway"
  }'
```

201 returns the created group. 409 if the name already exists for this portal user. 429 if you have ≥20 groups.

### List

```bash
curl -s "$BASE/policy-groups?page=1&page_size=10" \
  -H "Authorization: Bearer $TOKEN" | jq .
```

Optional filter: `&name=hr` (case-insensitive substring). `page_size` is capped at 100.

### Get

```bash
curl -s "$BASE/policy-groups/$GROUP_ID" \
  -H "Authorization: Bearer $TOKEN" | jq .
```

### Update

```bash
curl -s -X PUT "$BASE/policy-groups/$GROUP_ID" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "hr-prod-gateway",
    "description": "Updated description"
  }'
```

Both `name` and `description` are optional in the payload — send the fields you want to change.

### Delete (cascade)

```bash
curl -s -X DELETE "$BASE/policy-groups/$GROUP_ID" \
  -H "Authorization: Bearer $TOKEN"
```

**Irreversible.** Removes the group and every policy in it. Surface this warning to the user before executing.

---

## Policies

All policy endpoints are nested under a group.

### Create

```bash
curl -s -X POST "$BASE/policy-groups/$GROUP_ID/policies" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "allow-active-hr-analysts",
    "description": "Allow active HR analysts to call any tool",
    "statement": {
      "effect": "allow",
      "principal": "*",
      "actions": ["*"],
      "resources": ["*"],
      "condition": {
        "equals":    { "principal.department": "HR",
                       "principal.role":       "analyst" },
        "notEquals": { "principal.status": "suspended" }
      }
    }
  }'
```

201 returns the created policy. 400 with a precise message if the template is invalid (echo the message verbatim — it tells the user exactly which field/operator/key is the problem). 409 on name conflict. 429 if you have ≥10 policies in the group.

### List

```bash
curl -s "$BASE/policy-groups/$GROUP_ID/policies?page=1&page_size=10" \
  -H "Authorization: Bearer $TOKEN" | jq .
```

Optional `&name=...` substring filter. 404 if `$GROUP_ID` does not exist.

### Get

```bash
curl -s "$BASE/policy-groups/$GROUP_ID/policies/$POLICY_ID" \
  -H "Authorization: Bearer $TOKEN" | jq .
```

### Update

```bash
curl -s -X PUT "$BASE/policy-groups/$GROUP_ID/policies/$POLICY_ID" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "active": false,
    "statement": {
      "effect": "allow",
      "principal": "*",
      "actions": ["*"],
      "resources": ["*"],
      "condition": {
        "equals": { "principal.role": "analyst" }
      }
    }
  }'
```

All fields are optional. If `statement` is included it must be a complete `statement` body (not a patch). Use `"active": false` to soft-disable a rule without deleting it.

### Delete

```bash
curl -s -X DELETE "$BASE/policy-groups/$GROUP_ID/policies/$POLICY_ID" \
  -H "Authorization: Bearer $TOKEN"
```

---

## Error Body Shape

400 / 401 / 403 / 404 / 409 / 429 / 500 all use the same envelope:

```json
{
  "error": {
    "code": "BAD_REQUEST",
    "message": "operator \"is\" is not supported; see GET /api/v1/policy/condition-operators"
  }
}
```

When confirming an error with the user, quote `error.message` directly — it pinpoints the exact problem.

---

## Testing a Policy

The Policy service does not expose a public dry-run endpoint. To verify a rule, exercise the resource type's enforcement point with the same identity and inspect the response. For the `gateway` resource type, that means sending the would-be JSON-RPC call through the Resource Gateway — it evaluates policies live for every request. Other resource types, when added, will have their own enforcement entry points.
