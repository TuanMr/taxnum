# Resource Gateway — API Recipes

Curl recipes for every public endpoint. All examples assume:

```bash
BASE=https://agentbase.api.vngcloud.vn/gateway/api/v1
TOKEN=$(bash .claude/skills/agentbase/scripts/get_token.sh)
```

Auth header is `Authorization: Bearer $TOKEN` on every call. Async transitions return **202 Accepted**; metadata-only PATCH returns **200 OK**. Every mutable response carries an `ETag: "<resourceVersion>"` header — capture it and pass back as `If-Match` on the next mutation.

Pagination on `GET /gateways` is **1-indexed**: `page=1`, `pageSize=50` (max `200`). Response shape: `{ items, pagination: { page, pageSize, totalItems, hasMore } }`.

---

## Flavors

List compute sizes eligible for a gateway. Filter by `networkMode` when looking for PRIVATE-eligible flavors.

```bash
# PUBLIC flavors
curl -sS "$BASE/flavors?resourceType=GATEWAY" \
  -H "Authorization: Bearer $TOKEN" | jq .

# PRIVATE flavors in a given zone
curl -sS "$BASE/flavors?resourceType=GATEWAY&networkMode=PRIVATE&zoneId=$ZONE_ID" \
  -H "Authorization: Bearer $TOKEN" | jq .
```

Response:

```json
{
  "items": [
    {
      "id": "gw-1x1",
      "displayName": "Gateway 1x1",
      "cpu": 1,
      "memoryGi": 1,
      "availability": "YES",
      "networkModes": ["PUBLIC", "PRIVATE"],
      "resourceTypes": ["GATEWAY"],
      "sortOrder": 10
    }
  ]
}
```

Only show flavors whose `availability` is `YES` to the user. `UNKNOWN` is acceptable as a fallback when the capacity service is unreachable; `NO` means out of stock for the requested mode/zone.

---

## List gateways

```bash
curl -sS "$BASE/gateways?page=1&pageSize=50" \
  -H "Authorization: Bearer $TOKEN" | jq .
```

Optional filters:

| Filter | Example |
|---|---|
| `state` | `&state=ACTIVE` |
| `policyGroupId` | `&policyGroupId=$GROUP_ID` |

Response:

```json
{
  "items": [ /* GatewayResponse, see Get */ ],
  "pagination": { "page": 1, "pageSize": 50, "totalItems": 3, "hasMore": false }
}
```

---

## Create gateway

`POST /gateways` is **asynchronous** and returns **202 Accepted** with the freshly created gateway in `WAITING_CREATING` state and an `ETag` header. Poll `GET /gateways/{name}` until `state=ACTIVE` (or surfaces a terminal error state).

```bash
curl -sS -X POST "$BASE/gateways" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -i -d '{
    "name":        "hr-prod",
    "displayName": "HR Production Gateway",
    "description": "Fronts internal HR MCP servers",
    "networkMode": "PUBLIC",
    "flavorId":    "gw-1x1",
    "replicas":    1,
    "inboundAuth": { "mode": "IAM" },
    "policyGroupId": "pg-abc123",
    "targets": [
      {
        "name":     "hr",
        "type":     "MCP",
        "endpoint": "https://hr-mcp.example.com",
        "outboundAuth": {
          "type":              "APIKEY",
          "flow":              "2LO",
          "headerName":        "X-Api-Key",
          "headerValuePrefix": "",
          "providerName":      "hr-mcp-apikey"
        }
      }
    ]
  }'
```

### Sealed fields (cannot be patched — recreate to change)

`name`, `networkMode`, `privateNetwork.vpcId`, `privateNetwork.subnetId`, `flavorId`, `replicas`.

### Validation summary

| Field | Rule |
|---|---|
| `name` | `^[a-z0-9-]+$`, length 3–40, no leading/trailing dash. |
| `displayName` | optional, ≤100, `[A-Za-z0-9_.-]`. |
| `description` | optional, ≤500, `[A-Za-z0-9_.\-, ]`. |
| `networkMode` | `PUBLIC` or `PRIVATE`. |
| `privateNetwork.vpcId` / `subnetId` | required when `networkMode=PRIVATE`, ≤50, `[A-Za-z0-9_-]`. |
| `privateNetwork.routes[]` | optional, ≤50 entries, each a private IPv4 CIDR (RFC 1918). IPv6 and public ranges are rejected. |
| `flavorId` | must come from `GET /flavors` and match the chosen `networkMode` + `zoneId`. |
| `replicas` | integer 1–10. |
| `inboundAuth` | see `inbound-auth.md`. |
| `targets[]` | length ≤ `gateway.maxTargets` (operator-configured, default 50). Each target uses an `outboundAuth` block per `outbound-auth.md`. Target `name` is `^[a-z0-9-]+$`, length 3–50. Target `endpoint` must start with `https://` and be ≤1000 chars. |
| `policyGroupId` | optional, ≤50, `[A-Za-z0-9_-]`. Must reference an existing Policy Group (see `/agentbase-policy`). |

### Error codes

| Code | Meaning |
|---|---|
| 400 | Field-level validation error. Body contains a precise message — surface it verbatim. |
| 409 | A gateway with this `name` already exists for the caller. |
| 422 | Quota exceeded (gateways per user), no eligible cluster/flavor, or `targets.length > gateway.maxTargets`. |

---

## Get gateway

```bash
curl -sS "$BASE/gateways/$NAME" \
  -H "Authorization: Bearer $TOKEN" \
  -i | jq .
```

`-i` exposes the `ETag` header so you can capture `resourceVersion` for the next PATCH.

Response (`GatewayResponse`):

```json
{
  "id":          "gw-uuid",
  "name":        "hr-prod",
  "displayName": "HR Production Gateway",
  "description": "...",
  "state":       "ACTIVE",
  "networkMode": "PUBLIC",
  "privateNetwork": { "vpcId": "...", "subnetId": "...", "routes": ["10.0.0.0/16"] },
  "flavor":      { "id": "gw-1x1", "displayName": "Gateway 1x1", "cpu": 1, "memoryGi": 1 },
  "replicas":    1,
  "endpoint":    "https://hr-prod-<hash>.gateway.agentbase.vngcloud.vn",
  "inboundAuth": { "mode": "JWT", "jwt": { /* see inbound-auth.md */ } },
  "targets":     [ { "name": "hr", "type": "MCP", "endpoint": "...", "outboundAuth": { /* ... */ } } ],
  "policyGroupId": "pg-abc123",
  "iam":         { "serviceAccountId": "sa-...", "lastAuthFailureAt": null },
  "createdAt":   "2026-05-15T03:04:05Z",
  "updatedAt":   "2026-05-15T03:05:10Z",
  "appliedResourceVersion": "42",
  "appliedAt":   "2026-05-15T03:05:10Z",
  "previousAppliedSpec": { /* snapshot of the previous applied spec */ },
  "lastError":   null,
  "agentIdentityName": "agent-..."
}
```

Headers: `ETag: "42"` — quote characters around the version are part of the value (RFC 7232).

Error codes: `401`, `404`, `500`.

---

## Update gateway (JSON Merge Patch, RFC 7396)

PATCH updates only the user-mutable fields. Returns **200** for metadata-only changes (no rollout) or **202** when the change triggers a runtime rollout (state moves to `UPDATING`).

```bash
curl -sS -X PATCH "$BASE/gateways/$NAME" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -H 'If-Match: "42"' \
  -i -d '{
    "displayName":  "HR Prod (renamed)",
    "description":  null,
    "policyGroupId": "pg-newgroup",
    "inboundAuth": { "mode": "IAM" },
    "targets": [
      {
        "name": "hr",
        "type": "MCP",
        "endpoint": "https://hr-mcp.example.com",
        "outboundAuth": { "type": "APIKEY", "flow": "2LO", "headerName": "X-Api-Key", "headerValuePrefix": "", "providerName": "hr-mcp-apikey" }
      },
      {
        "name": "payroll",
        "type": "MCP",
        "endpoint": "https://payroll-mcp.example.com",
        "outboundAuth": { "type": "APIKEY", "flow": "2LO", "headerName": "X-Api-Key", "headerValuePrefix": "", "providerName": "payroll-mcp-apikey" }
      }
    ]
  }'
```

### Merge Patch semantics — pitfalls

| Intent | Send |
|---|---|
| Leave a field untouched | **Omit** it. |
| Clear an optional string (`displayName`, `description`) | `null`. |
| Unbind the Policy Group | `"policyGroupId": null`. **Not** `""` — empty string is rejected. |
| Replace the targets list | The **entire** desired array. There is no add/remove operator. `[]` clears all targets. **`null` is rejected** for `targets`. |
| Replace inbound auth | The **entire** `inboundAuth` object — Merge Patch does not deep-merge nested config. To remove JWT details when switching `JWT → IAM`, send `{ "mode": "IAM" }` and omit `jwt`. |

### Sealed fields

`name`, `networkMode`, `privateNetwork.vpcId`, `privateNetwork.subnetId`, `flavorId`, `replicas`. Attempting to PATCH any of these fails validation. To change them, `DELETE` and re-`POST`.

### Headers

| Header | Purpose |
|---|---|
| `If-Match: "<resourceVersion>"` | Optional. The server CAS-checks the stored version anyway; passing `If-Match` lets you reject concurrent edits up-front. On mismatch → **412 Precondition Failed**. |

### Error codes

| Code | Meaning |
|---|---|
| 200 | Metadata-only change applied; no rollout. |
| 202 | Runtime-affecting change accepted; state → `UPDATING`. |
| 400 | Validation error or attempted patch of a sealed field. |
| 409 | Gateway is in a conflicting state (e.g., `DELETING`). |
| 412 | Stale `If-Match` — re-`GET`, rebase, retry. |
| 422 | New `targets` array exceeds `gateway.maxTargets`. |

---

## Delete gateway

```bash
curl -sS -X DELETE "$BASE/gateways/$NAME" \
  -H "Authorization: Bearer $TOKEN" \
  -i
```

Returns **202** and moves the gateway to `WAITING_DELETING` or `DELETING`. Idempotent except when a delete is already in flight (`409`). After the async cleanup completes, the gateway disappears from `GET /gateways`. Bound `policyGroupId` is **not** deleted — manage policies separately via `/agentbase-policy`.

Error codes: `401`, `404`, `409` (delete already in progress).

---

## Private network routes (PRIVATE only)

Available only when `networkMode=PRIVATE`. Returns **404** otherwise.

### Get current routes

```bash
curl -sS "$BASE/gateways/$NAME/private-network/routes" \
  -H "Authorization: Bearer $TOKEN" \
  -i | jq .
```

Response:

```json
{ "routes": ["10.0.0.0/16", "172.16.0.0/12"], "state": "ACTIVE", "resourceVersion": "57" }
```

Headers: `ETag: "57"`.

### Replace routes

`PUT` replaces the **entire** list atomically. There is no add/remove diff endpoint — compute the desired full list locally and `PUT` it. Gateway must be `ACTIVE` or `UPDATE_ERROR`.

```bash
curl -sS -X PUT "$BASE/gateways/$NAME/private-network/routes" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -H 'If-Match: "57"' \
  -i -d '{
    "routes": ["10.0.0.0/16", "172.16.0.0/12", "192.168.10.0/24"]
  }'
```

Returns **200** (no change) or **202** (state → `UPDATING`). Constraints: ≤50 entries, IPv4 CIDR only, private ranges only.

### Error codes

| Code | Meaning |
|---|---|
| 400 | Invalid CIDR, IPv6, public range, missing `routes` key, or empty body. |
| 404 | Gateway not found, or gateway is `PUBLIC` (no routes resource). |
| 409 | Gateway is not in `ACTIVE` / `UPDATE_ERROR` state. |
| 412 | Stale `If-Match`. |

---

## Repair service account

Use only when the gateway's IAM service account has been reset, disabled, or deleted out-of-band — symptoms include callers receiving 502 from the gateway and `iam.lastAuthFailureAt` being set on the `GET` response.

```bash
curl -sS -X POST "$BASE/gateways/$NAME/service-account/repair" \
  -H "Authorization: Bearer $TOKEN" \
  -i
```

Returns the updated `GatewayResponse` with a fresh `iam.serviceAccountId` and `lastAuthFailureAt: null`. A brief rollout follows; poll `GET` until `state=ACTIVE`.

### Error codes

| Code | Meaning |
|---|---|
| 401 | Unauthorized. |
| 404 | Gateway not found. |
| 409 | Gateway not in `ACTIVE` / `UPDATE_ERROR` (cannot repair during create/delete). |
| 412 | A concurrent repair raced this call. Re-`GET`, retry. |
| 502 | Upstream IAM rejected the rebuild. Surface the message; retry after fixing IAM-level issues. |
