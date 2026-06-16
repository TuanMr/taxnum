# Resource Gateway — End-to-End Examples

Realistic, runnable scenarios. Each example shows the full lifecycle: create → verify → use → adjust → tear down. All examples assume:

```bash
BASE=https://agentbase.api.vngcloud.vn/gateway/api/v1
TOKEN=$(bash .claude/skills/agentbase/scripts/get_token.sh)
```

---

## 1. PUBLIC gateway, IAM inbound, one APIKEY target

Use case: an internal agent (deployed via `/agentbase-deploy`) needs to call a hosted HR MCP server that requires an API key.

### Step 1 — Discover flavors

```bash
curl -sS "$BASE/flavors?resourceType=GATEWAY" \
  -H "Authorization: Bearer $TOKEN" | jq '.items[] | select(.availability=="YES")'
```

Pick one and substitute its `id` (here written as `<FLAVOR_ID>`) into the create payload below. Never hardcode a flavor ID — IDs differ per environment.

### Step 2 — Pre-register the API key in AgentBase Identity

The gateway never stores the raw API key. Register it via `/agentbase-identity` with a provider name your team will reuse (here `hr-mcp-apikey`). Confirm the provider exists before continuing.

### Step 3 — Create the gateway

```bash
curl -sS -X POST "$BASE/gateways" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -i -d '{
    "name":        "hr-prod",
    "displayName": "HR Production Gateway",
    "description": "Internal agents -> HR MCP",
    "networkMode": "PUBLIC",
    "flavorId":    "<FLAVOR_ID>",
    "replicas":    1,
    "inboundAuth": { "mode": "IAM" },
    "targets": [
      {
        "name":     "hr",
        "type":     "MCP",
        "endpoint": "https://hr-mcp.internal.example.com",
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

Capture `ETag` from the response headers. Status returns **202**; gateway is in `WAITING_CREATING`.

### Step 4 — Poll for ACTIVE

```bash
until [ "$(curl -sS "$BASE/gateways/hr-prod" -H "Authorization: Bearer $TOKEN" | jq -r .state)" = "ACTIVE" ]; do
  sleep 5
done
curl -sS "$BASE/gateways/hr-prod" -H "Authorization: Bearer $TOKEN" | jq '{state, endpoint, iam}'
```

The `endpoint` field is the URL agents should call.

### Step 5 — Bind a Policy Group later (optional)

To restrict which IAM service accounts can call `hr__lookup_employee`:

```bash
# 1. Create a Policy Group + policy via /agentbase-policy first; capture $POLICY_GROUP_ID.
# 2. Patch the gateway to bind it (resourceVersion captured from the previous GET):
curl -sS -X PATCH "$BASE/gateways/hr-prod" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -H "If-Match: \"$RESOURCE_VERSION\"" \
  -d "{ \"policyGroupId\": \"$POLICY_GROUP_ID\" }"
```

---

## 2. PUBLIC gateway, JWT inbound (Okta), two targets — APIKEY + OAUTH 3LO

Use case: a browser-based assistant in front of two SaaS systems. End users authenticate via Okta (JWT); calls to the HR MCP use an API key; calls to a Google Calendar MCP need 3LO consent on behalf of the end user.

### Step 1 — Register OAuth providers in AgentBase Identity

- `hr-mcp-apikey` — API key for the HR target (as in example 1).
- `google-calendar-oauth` — Google OAuth client (`client_id`, `client_secret`, authorize/token endpoints) for the 3LO target.

### Step 2 — Create the gateway with JWT inbound

```bash
curl -sS -X POST "$BASE/gateways" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -i -d '{
    "name":        "assistant-prod",
    "displayName": "Assistant Production Gateway",
    "networkMode": "PUBLIC",
    "flavorId":    "<FLAVOR_ID>",
    "replicas":    2,
    "inboundAuth": {
      "mode": "JWT",
      "jwt": {
        "source":           "DISCOVERY",
        "discoveryUrl":     "https://dev-12345.okta.com/.well-known/openid-configuration",
        "principalClaim":   "sub",
        "allowedAudiences": ["api://assistant"],
        "allowedScopes":    ["mcp.invoke"]
      }
    },
    "targets": [
      {
        "name":     "hr",
        "type":     "MCP",
        "endpoint": "https://hr-mcp.internal.example.com",
        "outboundAuth": {
          "type":              "APIKEY",
          "flow":              "2LO",
          "headerName":        "X-Api-Key",
          "headerValuePrefix": "",
          "providerName":      "hr-mcp-apikey"
        }
      },
      {
        "name":     "calendar",
        "type":     "MCP",
        "endpoint": "https://calendar-mcp.example.com",
        "outboundAuth": {
          "type":         "OAUTH",
          "flow":         "3LO",
          "providerName": "google-calendar-oauth",
          "scopes":       ["https://www.googleapis.com/auth/calendar.readonly"],
          "returnUrl":    "https://assistant-prod-<hash>.gateway.agentbase.vngcloud.vn/oauth/return",
          "customParameters": { "prompt": "consent", "access_type": "offline" }
        }
      }
    ]
  }'
```

`returnUrl` for 3LO must match a redirect URI registered with the IdP. Use the gateway's actual endpoint URL (available after `state=ACTIVE`); if you create the gateway first, take the returned endpoint, register it with the IdP, then PATCH `outboundAuth.returnUrl` on the target.

### Step 3 — Verify each path

After `state=ACTIVE`, two distinct behaviours:

- `tools/call` to `target=hr, tool=lookup_employee` → gateway attaches `X-Api-Key: <key>` and forwards.
- `tools/call` to `target=calendar, tool=list_events` → first call redirects the end user through Okta-issued state to Google's authorize endpoint; subsequent calls reuse the cached refresh token.

---

## 3. PRIVATE / VPC gateway with private targets and route updates

Use case: every target lives in a VNG Cloud VPC, the gateway must join that VPC. The user also wants to add another private CIDR later.

### Step 1 — Discover VPC and subnet

Use the shared vServer helper (same as `/agentbase-deploy`):

```bash
bash .claude/skills/agentbase/scripts/vserver.sh projects
bash .claude/skills/agentbase/scripts/vserver.sh vpcs $PROJECT_ID
bash .claude/skills/agentbase/scripts/vserver.sh subnets $PROJECT_ID $VPC_ID
bash .claude/skills/agentbase/scripts/vserver.sh validate-vpc $PROJECT_ID $VPC_ID
```

`validate-vpc` must succeed (vDNS enabled, no overlap with the system CIDR). If it fails, surface the JSON report and ask the user to pick a different VPC.

### Step 2 — List PRIVATE-eligible flavors

```bash
curl -sS "$BASE/flavors?resourceType=GATEWAY&networkMode=PRIVATE&zoneId=$ZONE_ID" \
  -H "Authorization: Bearer $TOKEN" | jq '.items[] | select(.availability=="YES")'
```

### Step 3 — Create the gateway

```bash
curl -sS -X POST "$BASE/gateways" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -i -d '{
    "name":        "internal-mcp",
    "networkMode": "PRIVATE",
    "privateNetwork": {
      "vpcId":    "'"$VPC_ID"'",
      "subnetId": "'"$SUBNET_ID"'",
      "routes":   ["10.0.0.0/16"]
    },
    "flavorId":  "<FLAVOR_ID>",
    "replicas":  2,
    "inboundAuth": { "mode": "IAM" },
    "targets": [
      {
        "name":     "inventory",
        "type":     "MCP",
        "endpoint": "https://10.0.5.20:8443",
        "outboundAuth": {
          "type":              "APIKEY",
          "flow":              "2LO",
          "headerName":        "X-Api-Key",
          "headerValuePrefix": "",
          "providerName":      "inventory-apikey"
        }
      }
    ]
  }'
```

### Step 4 — Later: add another private range

```bash
# 1. Get current routes + resourceVersion
ROUTES_RV=$(curl -sS -i "$BASE/gateways/internal-mcp/private-network/routes" \
  -H "Authorization: Bearer $TOKEN" | grep -i '^etag:' | awk '{print $2}' | tr -d '\r"')

# 2. Replace the whole list (full set, not a delta)
curl -sS -X PUT "$BASE/gateways/internal-mcp/private-network/routes" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -H "If-Match: \"$ROUTES_RV\"" \
  -i -d '{ "routes": ["10.0.0.0/16", "172.16.0.0/12"] }'
```

Returns **202**; poll `GET /gateways/internal-mcp` until `state=ACTIVE`.

---

## 4. Recover a broken service account

Symptoms: callers receive 502 from the gateway, and `GET /gateways/{name}` shows `iam.lastAuthFailureAt` set to a recent timestamp.

```bash
# Confirm the symptom
curl -sS "$BASE/gateways/$NAME" \
  -H "Authorization: Bearer $TOKEN" | jq '{state, iam, lastError}'

# Trigger a repair (requires state ACTIVE or UPDATE_ERROR)
curl -sS -X POST "$BASE/gateways/$NAME/service-account/repair" \
  -H "Authorization: Bearer $TOKEN" -i

# Wait for the brief rollout
until [ "$(curl -sS "$BASE/gateways/$NAME" -H "Authorization: Bearer $TOKEN" | jq -r .state)" = "ACTIVE" ]; do
  sleep 5
done
```

After repair, `iam.serviceAccountId` may change and `lastAuthFailureAt` resets to `null`. If a downstream system pinned the previous service account ID for its own ACLs, update that ACL too.

---

## 5. Add a target without changing inbound auth

A common mistake is sending an `inboundAuth` block on every PATCH "just in case." Don't — PATCH is Merge Patch: send **only** what you want to change. To add a target to an existing gateway:

```bash
# 1. Get the current spec to capture both ETag and the existing targets list
GW=$(curl -sS -i "$BASE/gateways/$NAME" -H "Authorization: Bearer $TOKEN")
RV=$(printf '%s' "$GW" | grep -i '^etag:' | awk '{print $2}' | tr -d '\r"')
TARGETS=$(printf '%s' "$GW" | awk 'BEGIN{p=0} /^\{$/{p=1} p{print}' | jq '.targets')

# 2. Append the new target locally
NEW_TARGETS=$(echo "$TARGETS" | jq '. + [{
  name:"payroll", type:"MCP", endpoint:"https://payroll-mcp.example.com",
  outboundAuth:{ type:"APIKEY", flow:"2LO", headerName:"X-Api-Key", headerValuePrefix:"", providerName:"payroll-apikey" }
}]')

# 3. Send only the new targets list in the PATCH body
curl -sS -X PATCH "$BASE/gateways/$NAME" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -H "If-Match: \"$RV\"" \
  -d "$(jq -n --argjson t "$NEW_TARGETS" '{targets:$t}')"
```

Send `"targets": []` to remove all targets. Never `null`.

---

## 6. Delete the gateway

```bash
curl -sS -X DELETE "$BASE/gateways/$NAME" \
  -H "Authorization: Bearer $TOKEN" -i

# Optional: confirm it's gone (eventually 404 once async cleanup finishes)
until ! curl -sSf "$BASE/gateways/$NAME" -H "Authorization: Bearer $TOKEN" >/dev/null 2>&1; do
  sleep 5
done
```

Deletion does **not** clean up the bound Policy Group, registered Identity providers, or the upstream MCP servers themselves — manage those separately via `/agentbase-policy` and `/agentbase-identity`.
