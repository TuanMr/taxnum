# Custom Agent Runtime Management — Full Operations Reference

Detailed operations for managing **Custom Agents** (resource type `/agent-runtimes`) on GreenNode AgentBase Runtime Service. A Custom Agent is a user-built application whose code is packaged into a Docker image the user supplies. For **OpenClaw** (pre-built template agents like Telegram/Zalo bots, resource type `/openclaws`), see `references/openclaw-ops.md` and use `openclaw.sh`.

All operations use the runtime script: `bash .claude/skills/agentbase/scripts/runtime.sh`

The script handles authentication (auto token refresh), response redaction (sensitive fields), and error handling automatically.

---

## create -- Create a new runtime

### Interactive Parameter Gathering

Before creating, gather the following from the user. Ask for required info and recommend sensible defaults for the rest.

**Step 1 - Ask the user for required info:**
- **Name**: Runtime name (lowercase, hyphens allowed). If not provided, ask.
- **Image URL**: Container image URL (e.g. `registry.example.com/my-agent:latest`). Must be provided.
- **Private registry?** Ask explicitly: "Is this image from a private registry?" If yes, `imageAuth` is **required** — collect `username` and `password` (Docker credentials of a user with pull access to the repo). Without these, AgentBase cannot pull the image.

**Step 2 - Recommend defaults, let user override:**

Present a summary with recommended values and ask the user to confirm or adjust:

| Parameter | Recommended | Options |
|-----------|-------------|---------|
| **Flavor** | `1x1-general` (1 CPU, 1 GB RAM) | Fetch available flavors via `runtime.sh flavors` and show as table |
| **Min replicas** | `1` | Range: 1-10 |
| **Max replicas** | `1` | Range: 1-10. Set >1 for auto-scaling |
| **CPU scale threshold** | `50`% | Range: 10-90%. Scale up when CPU exceeds this |
| **Memory scale threshold** | `50`% | Range: 10-90%. Scale up when memory exceeds this |
| **Environment variables** | `{}` | Key-value pairs to inject into container. User provides env file path (see below) |
| **Command** | `[]` (use image default) | Override Docker ENTRYPOINT |
| **Args** | `[]` (use image default) | Override Docker CMD |
| **Description** | `""` | Optional description |
| **Network mode** | `PUBLIC` (omit `networkConfig`) | `PUBLIC` (server default) or `VPC`. See "Network Configuration" below |

**Step 3 - Environment variables file:**

You **MUST ask the user** (using AskUserQuestion) to specify the exact path to their env file — do NOT assume `.env` or any default. Example: "What is the path to your environment variables file? (e.g., `.env`, `.env.production`, or 'none' if not needed)". This file will be passed as `--env-file <path>` to the runtime script. **NEVER read the env file yourself** — the script reads it internally. Remind the user to review their env file before proceeding and ensure it does not contain auto-injected variables (`GREENNODE_CLIENT_ID`, `GREENNODE_CLIENT_SECRET`, `GREENNODE_AGENT_IDENTITY`, `GREENNODE_ENDPOINT_URL`). If the user has no env file, proceed without `--env-file`.

**Step 4 - Confirm and create:**

Show the final configuration and ask the user to confirm before sending.

### Script Reference

**Required fields** (all fields are required by the API):
- `name` (string, min 1 char) -- unique name for the runtime
- `description` (string) -- description of the runtime (can be empty `""`)
- `imageUrl` (string, min 1 char) -- container image URL
- `command` (string array) -- use `[]` to keep image defaults
- `args` (string array) -- use `[]` to keep image defaults
- `environmentVariables` (object, string key-value pairs) -- use `{}` if none. Key pattern: `^[a-zA-Z_][a-zA-Z0-9_.-]*$`
- `flavorId` (string, min 1 char) -- compute flavor ID
- `autoscaling` (object):
  - `minReplicas` (int, 1-10)
  - `maxReplicas` (int, 1-10)
  - `cpuUtilization` (int, 10-90)
  - `memoryUtilization` (int, 10-90)

**Required for private registry** (`imageAuth` object):
- `imageAuth.enabled` (bool, default `true`)
- `imageAuth.username` (string, min 1 char) -- Docker username or robot account with pull access
- `imageAuth.password` (string, min 1 char) -- Docker password or access token

> Without `imageAuth`, AgentBase cannot pull images from private registries — the runtime will fail with an image pull error.

**Optional `networkConfig` object** (Custom Agent only; OpenClaw does not accept it):

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `mode` | string | required if object present | `PUBLIC` (default when `networkConfig` is omitted) or `VPC` (case-insensitive on input, normalized to upper-case). |
| `vpcId` | string | required when `mode=VPC` | VNG Cloud VPC ID. The VPC must have **DNS enabled**, otherwise create/update is rejected with HTTP 400. |
| `subnetId` | string | required when `mode=VPC` | Subnet inside the chosen VPC. The API calls VServer to verify existence; 404 → HTTP 400. |
| `routeCidrs` | string[] | optional | Extra **private** CIDR ranges (RFC 1918) routed from the runtime pod into the VPC. Each entry must be a valid private CIDR and must not overlap a platform-disallowed range. Public CIDRs are rejected. |

Validation rules (enforced server-side; mirror these in the user-facing prompt before submitting):
- `mode=PUBLIC` requires the chosen flavor to support resource type `agent-runtime`.
- `mode=VPC` requires the chosen flavor to support resource type `agent-runtime-vpc` — list flavors with `runtime.sh flavors` and inspect `supportedResourceTypes` to filter.
- The selected VPC's CIDR is also checked against the platform-disallowed (system) CIDR — if it overlaps, the user must pick a different VPC. Default system CIDR: `172.30.0.0/16` (overridable via `AGENTBASE_SYSTEM_CIDR`; will eventually be published on the platform docs).
- Changing `networkConfig.mode` on an existing runtime via `update` causes endpoints to be recreated under the new mode.

### Discovering `vpcId` and `subnetId` — vServer API

Users rarely know their VPC/subnet UUIDs off the top of their heads. Use `vserver.sh` (wraps the vServer API at `https://hcm-3.api.vngcloud.vn/vserver/vserver-gateway`; switch region with `GREENNODE_REGION=han`) to list and validate them:

```bash
# 1. List projects (most users have a single project)
bash .claude/skills/agentbase/scripts/vserver.sh projects

# 2. List VPCs in the project — filtered to id, name, cidr, status, dnsStatus
bash .claude/skills/agentbase/scripts/vserver.sh vpcs <projectId>

# 3. List subnets of a VPC — filtered to id, name, cidr, status
bash .claude/skills/agentbase/scripts/vserver.sh subnets <projectId> <vpcId>

# 4. Validate the VPC is usable for Custom Agent VPC mode
bash .claude/skills/agentbase/scripts/vserver.sh validate-vpc <projectId> <vpcId>
```

`validate-vpc` runs **both** pre-flight checks before you call `runtime.sh create`:
1. vDNS is enabled on the VPC (otherwise the runtime API rejects with HTTP 400).
2. The VPC CIDR does not overlap the system CIDR (`AGENTBASE_SYSTEM_CIDR`, default `172.30.0.0/16`).

Exit status is `0` when both checks pass, `1` otherwise; the JSON report names which check failed.

**Example (public registry)**:
```bash
bash .claude/skills/agentbase/scripts/runtime.sh create \
  --name my-agent \
  --image "registry.example.com/my-agent:v1" \
  --flavor 1x1-general
```

**Example (private registry — imageAuth required)**:
```bash
bash .claude/skills/agentbase/scripts/runtime.sh create \
  --name my-agent \
  --image "registry.example.com/my-agent:v1" \
  --flavor 1x1-general \
  --registry-credentials-file <path-to-credentials-file>
```

**Example (with env file and autoscaling)**:
```bash
bash .claude/skills/agentbase/scripts/runtime.sh create \
  --name my-agent \
  --image "registry.example.com/my-agent:v1" \
  --flavor 1x1-general \
  --env-file .env \
  --description "My agent runtime" \
  --min-replicas 1 \
  --max-replicas 3 \
  --cpu-scale 60 \
  --mem-scale 60
```

**Example (VPC network mode)**:
```bash
bash .claude/skills/agentbase/scripts/runtime.sh create \
  --name my-agent \
  --image "registry.example.com/my-agent:v1" \
  --flavor 1x1-general-vpc \
  --network-mode VPC \
  --vpc-id "<vpc-uuid>" \
  --subnet-id "<subnet-uuid>" \
  --route-cidrs "10.10.0.0/16,192.168.50.0/24"
```
Omit `--network-mode` entirely to keep the default `PUBLIC` behaviour (the script then sends no `networkConfig` field, matching legacy runtimes).

**Behavior**: Creating a runtime automatically creates a `DEFAULT` endpoint that tracks the latest version.

**Note on `command` and `args`**: These follow the Kubernetes container spec convention:
- `command` overrides the Docker image's `ENTRYPOINT` (e.g. `["python"]`)
- `args` overrides the Docker image's `CMD` (e.g. `["main.py"]`)
- Use empty arrays `[]` to keep the image's defaults.

---

## list -- List all runtimes

**Note**: Runtime Service uses 1-indexed pagination (page=1 is first page).

```bash
bash .claude/skills/agentbase/scripts/runtime.sh list --page 1 --size 20
```

**Response**: `{ "listData": [...], "page": 1, "pageSize": 20, "totalPage": 1, "totalItem": 3 }`

Display results as a table: ID, Name, Status, Description, Created.

---

## get [id] -- Get runtime details

```bash
bash .claude/skills/agentbase/scripts/runtime.sh get $RUNTIME_ID
```

**Response fields**: `id`, `name`, `description`, `status`, `statusReason`, `createdAt`, `updatedAt`.

> **Note**: The runtime response does NOT include `flavorId`, `imageUrl`, `environmentVariables`, or `autoscaling`. To get these details, query the versions endpoint: `runtime.sh versions $RUNTIME_ID`.

---

## update [id] -- Update a runtime (creates new version)

```bash
bash .claude/skills/agentbase/scripts/runtime.sh update $RUNTIME_ID \
  --image "registry.example.com/my-agent:v2" \
  --flavor 1x1-general
```

**Body fields** (same as create minus `name`): `description`, `imageUrl`, `imageAuth`, `command`, `args`, `environmentVariables`, `flavorId`, `autoscaling`, `networkConfig`. All fields except `imageAuth` and `networkConfig` are required.

**Behavior**: Each update creates a new version. The `DEFAULT` endpoint automatically updates to the new version.

> **Switching network mode**: If the new version's `networkConfig.mode` differs from the previous version's, the endpoint is recreated under the new mode (the public/VPC paths are mutually exclusive). Expect a brief endpoint downtime while the new pod comes up. If `--network-mode` is omitted, the server defaults to `PUBLIC` — passing nothing on an existing VPC runtime will move it back to PUBLIC. Always re-pass the previous network flags when you want to keep VPC mode.

---

## delete [id] -- Delete a runtime

**Before deleting**: Consider exporting or noting the resource configuration, as deletion is irreversible. There is no undo.

**Constraint**: A runtime can only be deleted when it has no custom endpoints (only the DEFAULT endpoint or no endpoints at all). If custom endpoints exist, the API will reject the deletion. Delete all custom endpoints first, then delete the runtime.

```bash
# 1. List endpoints and delete any custom (non-DEFAULT) endpoints first
bash .claude/skills/agentbase/scripts/runtime.sh endpoints list $RUNTIME_ID
bash .claude/skills/agentbase/scripts/runtime.sh endpoints delete $RUNTIME_ID $CUSTOM_ENDPOINT_ID

# 2. Then delete the runtime
bash .claude/skills/agentbase/scripts/runtime.sh delete $RUNTIME_ID
```

**Warning**: This permanently deletes the runtime and all its endpoints. Confirm with the user before executing.

---

## endpoints [id] -- Manage endpoints

**List endpoints**:
```bash
bash .claude/skills/agentbase/scripts/runtime.sh endpoints list $RUNTIME_ID
```

**Create endpoint**:
```bash
bash .claude/skills/agentbase/scripts/runtime.sh endpoints create $RUNTIME_ID \
  --name canary --version 2
```

**Update endpoint version**:
```bash
bash .claude/skills/agentbase/scripts/runtime.sh endpoints update $RUNTIME_ID $ENDPOINT_ID \
  --version 3
```

**Delete endpoint**:
```bash
bash .claude/skills/agentbase/scripts/runtime.sh endpoints delete $RUNTIME_ID $ENDPOINT_ID
```

**Start / stop endpoint** (lifecycle control — stop halts the endpoint from serving traffic without deleting it; start resumes it):
```bash
bash .claude/skills/agentbase/scripts/runtime.sh endpoints stop  $RUNTIME_ID $ENDPOINT_ID
bash .claude/skills/agentbase/scripts/runtime.sh endpoints start $RUNTIME_ID $ENDPOINT_ID
```
Both return HTTP 200 with no body. After issuing, poll `endpoints list` and watch the endpoint `status` change to confirm the transition completed. **Confirm with the user before stopping** — a stopped endpoint stops serving traffic.

**Endpoint response fields**: `id`, `agentRuntimeId`, `name`, `version`, `currentReplicaCount`, `url`, `status`, `createdAt`, `updatedAt`.

**Endpoint logs**:
```bash
bash .claude/skills/agentbase/scripts/runtime.sh endpoints logs $RUNTIME_ID $ENDPOINT_ID \
  --from-time "2024-01-01T00:00:00Z" --to-time "2024-01-02T00:00:00Z"
```

**Endpoint metrics**:
```bash
bash .claude/skills/agentbase/scripts/runtime.sh endpoints metrics $RUNTIME_ID $ENDPOINT_ID \
  --from-time "2024-01-01T00:00:00Z" --to-time "2024-01-02T00:00:00Z"
```

---

## versions [id] -- List runtime versions

```bash
bash .claude/skills/agentbase/scripts/runtime.sh versions $RUNTIME_ID --page 1 --size 20
```

**Version fields**: `agentRuntimeId`, `version`, `description`, `imageUrl`, `imageAuth` (with `enabled`, `username`, `encryptedPassword`), `command`, `args`, `environmentVariables`, `flavorId`, `autoscaling` (with `minReplicas`, `maxReplicas`, `cpuUtilization`, `memoryUtilization`), `networkConfig` (with `mode`, `vpcId`, `subnetId`, `routeCidrs` — `null` for legacy versions created before the field existed), `createdAt`.

Display as a table: Version, Image, Flavor, Created.

---

## status [id] -- Check runtime deployment status

Poll the runtime status using the get command and check the `status` field:

```bash
# Poll every 10 seconds until status is ACTIVE
while true; do
  STATUS=$(bash .claude/skills/agentbase/scripts/runtime.sh get $RUNTIME_ID | jq -r '.status')
  echo "Status: $STATUS"
  if [ "$STATUS" = "ACTIVE" ]; then break; fi
  sleep 10
done
```

**Possible statuses**: `CREATING`, `UPDATING`, `ACTIVE`, `ERROR`, `DELETING`.

---

## reset-service-account [id] -- Reset runtime service account credentials

```bash
bash .claude/skills/agentbase/scripts/runtime.sh reset-service-account $RUNTIME_ID
```

**Warning**: This regenerates the runtime's IAM service account credentials. The runtime will restart with new `GREENNODE_CLIENT_ID` and `GREENNODE_CLIENT_SECRET`. Confirm with the user before executing.

---

## logs [id] -- Fetch runtime logs

```bash
bash .claude/skills/agentbase/scripts/runtime.sh logs $RUNTIME_ID \
  --from 0 --limit 100 --query "error" \
  --from-time "2024-01-01T00:00:00Z" --to-time "2024-01-02T00:00:00Z"
```

---

## Available Flavors

To list compute flavors:

```bash
bash .claude/skills/agentbase/scripts/runtime.sh flavors
```

Default flavor: `1x1-general` (1 CPU, 1 GB RAM).
