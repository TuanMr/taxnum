---
name: agentbase-monitor
description: "Monitor, debug, view logs, metrics, and status dashboard for DEPLOYED AI agents. View runtime logs, endpoint logs, and resource metrics (CPU/RAM). Show unified dashboard of all platform resources. Trigger for show logs, check logs, what is wrong with my agent, agent crashed, debug my deployed agent, tail logs, agent is slow, agent status, show dashboard, platform overview, what do I have, list all resources, show my agents, inventory, performance, check metrics, resource usage, or any debugging/monitoring of a deployed agent. DO NOT use for managing runtime lifecycle (create/update/delete) — use /agentbase-deploy runtime. DO NOT use for local testing — use /agentbase-wizard test."
---

# AgentBase Monitor

Monitor, debug, and view status of agents running on GreenNode AgentBase Runtime.

- **Console**: https://aiplatform.console.vngcloud.vn/agent-runtime?tab=runtime

## Authentication

Read the shared auth setup reference at `/agentbase` skill's `references/auth-setup.md` for full IAM credential configuration. In brief: run `bash .claude/skills/agentbase/scripts/check_credentials.sh iam` to verify credentials are configured. **NEVER read `.greennode.json` or `.env` directly** — always use the helper scripts. If `check_credentials.sh iam` returns MISSING, **STOP — you MUST read** the **"If Credentials Are Not Found"** section in `/agentbase` skill's `references/auth-setup.md` and follow it exactly. Do NOT skip this or provide your own credential setup instructions.

---

## Interaction Guidelines

- **Never assume API response structure** — always inspect the actual response first before extracting or filtering data. Do not guess field names.
- **Guide first, act only when asked** — if the user asks "how to" view logs, metrics, or dashboard, respond with instructions and guidance only. Do NOT execute API calls unless they explicitly ask you to do it for them.
- **Read-only operations proceed directly** — for log and metric queries (runtime-logs, endpoint-logs, metrics) and dashboard views, proceed directly once you have the required IDs. If a runtime ID or endpoint ID is needed and not provided, list runtimes first and ask the user to pick one. Only skip the listing if the user has already provided a specific ID.
- **Never auto-decide parameters** — when an action requires parameters (e.g., runtime ID, endpoint ID, log offset, limit), always ask the user for each required value. You may recommend sensible defaults (e.g., limit=100), but never auto-select or impose values without the user's explicit agreement.
- **Present options, let user choose** — when there are multiple runtimes or endpoints to choose from, list them and let the user pick. Do not make the choice for them.
- **Always read full API response body** — when calling platform APIs, capture and read the full JSON response (not just status codes). This avoids misidentifying field names or data structures, ensures correct field extraction, and enables better error handling and debugging.
- **Handle errors gracefully** — if any individual API call fails, show available data and mark failed sections with the error. Do not retry automatically — offer the user to retry individual failed sections.

---

# Part 1: Observability (Logs & Metrics)

## Operations

### runtime-logs [id] -- View runtime logs

Fetch logs from an agent runtime container.

**Parameters**:
- `--from N` (int, max 5000) -- starting offset (0-based)
- `--limit N` (int, max 500) -- number of log lines to return
- `--from-time ISO` (string, optional) -- start of time range filter (ISO 8601)
- `--to-time ISO` (string, optional) -- end of time range filter (ISO 8601)
- `--query TEXT` (string, optional) -- keyword search filter
- `--order asc|desc` (string, optional) -- log ordering

**Response** (`LogSearchResult`): `totalCount` (int), `logs` (array of `LogRecord` with `timestamp` (string) and `content` (string)).

**Command**:
```bash
# Basic log fetch (most recent 100 entries)
bash .claude/skills/agentbase/scripts/runtime.sh logs $RUNTIME_ID --from 0 --limit 100

# With time range and keyword search
bash .claude/skills/agentbase/scripts/runtime.sh logs $RUNTIME_ID \
  --from 0 --limit 100 \
  --from-time "2026-03-13T00:00:00Z" \
  --to-time "2026-03-13T12:00:00Z" \
  --query "error"
```

**Tips**:
- Use `--from` to paginate through large log sets (e.g. `--from 100` to skip first 100 entries)
- Max `--limit` is 500, max `--from` is 5000
- Use `--query` to filter logs by keyword server-side (e.g. `--query "error"`)
- Use `--from-time`/`--to-time` to narrow logs to a specific time window
- Each log entry has `timestamp` and `content` fields

---

### endpoint-logs [id] [endpointId] -- View endpoint logs

Fetch logs from a specific endpoint within a runtime.

**Parameters**: Same as runtime-logs (`--from`, `--limit`, `--from-time`, `--to-time`, `--query`).

**Command**:
```bash
bash .claude/skills/agentbase/scripts/runtime.sh endpoints logs $RUNTIME_ID $ENDPOINT_ID \
  --from 0 --limit 100
```

---

### metrics [id] [endpointId] -- View endpoint resource metrics

Get CPU and RAM usage metrics for a specific endpoint. Supports historical time range queries.

**Query parameters**:
- `--from-time ISO` (string, optional) -- start of time range (ISO 8601)
- `--to-time ISO` (string, optional) -- end of time range (ISO 8601)

**Command**:
```bash
# Current metrics
bash .claude/skills/agentbase/scripts/runtime.sh endpoints metrics $RUNTIME_ID $ENDPOINT_ID

# Historical metrics with time range
bash .claude/skills/agentbase/scripts/runtime.sh endpoints metrics $RUNTIME_ID $ENDPOINT_ID \
  --from-time "2026-03-13T00:00:00Z" --to-time "2026-03-13T12:00:00Z"
```

**Response** (`AgentRuntimeEndpointMetrics`):
- `cpuCoresUsage` -- array of `{timestamp (date-time), value (double)}` data points
- `memoryBytesUsage` -- array of `{timestamp (date-time), value (int64)}` data points

---

### events [id] [endpointId] -- View infrastructure events for an endpoint

Fetch the infrastructure-level events emitted while deploying and running an endpoint. This is the **first place to look when an endpoint is not `ACTIVE` but the logs are empty** — startup failures (image pull errors, out-of-memory kills, scheduling/capacity failures, health-probe failures) surface here as events before any application log is produced.

**Command**:
```bash
bash .claude/skills/agentbase/scripts/runtime.sh endpoints events $RUNTIME_ID $ENDPOINT_ID
```

**Response**: array of event objects, each with:
- `message` (string) -- the event message (e.g. `Back-off pulling image ...`, `out of memory`, `insufficient capacity`)
- `lastTimestamp` (date-time) -- when the event last occurred

**Common event signatures** (match against the `message` text):

| Event message indicates | Meaning | Next step |
|------------------------|---------|-----------|
| Image pull failure (e.g. `pulling image` / `ErrImagePull`) | Image cannot be pulled | Verify `imageUrl` and registry credentials (`imageAuth`) on the runtime version |
| Out of memory (e.g. `OOM` / `out of memory`) | Instance exceeded its memory limit | Scale up the flavor or fix the memory leak (cross-check `metrics`) |
| Scheduling / capacity failure (e.g. `insufficient` / `no capacity`) | No capacity to place the instance | Usually a flavor/capacity issue — try a smaller flavor or retry later |
| Health probe failure (e.g. `probe failed`) | `/health` not returning 200 | Verify the health endpoint (see Log Analysis Guide) |
| Crash / restart loop | Instance keeps crashing on startup | Check endpoint logs for the startup traceback |

---

### traces -- Distributed tracing (passthrough)

Query distributed traces for agent runtimes. These commands are a **thin passthrough** to the platform's tracing backend: the accepted query parameters (other than `traceId` / `tagKey`) and the response body shape are defined by that backend, **not by the runtime API spec**. Pass backend query params verbatim via repeated `--param key=value`; the response is the backend's raw JSON string.

> **Param semantics not documented here.** Do NOT invent trace query param names. If the user needs specific filters (time range, service, tags, min duration, etc.), source the exact param keys from the tracing backend's own documentation or the console's network calls before using them. Without that, the commands still work as a raw passthrough.

**Commands**:
```bash
# Search traces (params forwarded to the tracing backend)
bash .claude/skills/agentbase/scripts/runtime.sh traces search --param key=value [--param key=value ...]

# Get a single trace by ID
bash .claude/skills/agentbase/scripts/runtime.sh traces get $TRACE_ID [--param key=value ...]

# List available values for a trace tag key (for building filters)
bash .claude/skills/agentbase/scripts/runtime.sh traces tag-values $TAG_KEY [--param key=value ...]
```

`--param` values are URL-encoded automatically. The response is returned as-is (a JSON string from the backend) — parse it according to the backend's schema.

---

## Current Limitations

| Feature | Status |
|---------|--------|
| Log filtering by level (INFO/WARN/ERROR) | Not supported — all log levels are returned together |
| Log time range filter | Supported — use `--from-time`/`--to-time` |
| Log keyword search | Supported — use `--query` |
| Historical metrics | Supported — use `--from-time`/`--to-time` |
| Log streaming/tailing | Not supported — use polling as a workaround (see below) |
| Alerting/thresholds | Not supported |

**Pseudo-tailing pattern**: To approximate log tailing, poll the logs command every 5-10 seconds with an increasing `--from` offset. Inform the user of the polling limit at the start (e.g., "Tailing logs for up to 5 minutes..."). After reaching the limit, inform the user and offer to restart tailing. Be mindful of rate limits:
```bash
OFFSET=0
LIMIT=100
MAX_POLLS=60
for i in $(seq 1 $MAX_POLLS); do
  RESULT=$(bash .claude/skills/agentbase/scripts/runtime.sh logs $RUNTIME_ID --from $OFFSET --limit $LIMIT)
  BATCH_SIZE=$(echo "$RESULT" | jq '.logs | length')
  if [ "$BATCH_SIZE" -gt 0 ] 2>/dev/null; then
    echo "$RESULT" | jq -r '.logs[].content'
    OFFSET=$((OFFSET + BATCH_SIZE))
  fi
  sleep 5
done
```

---

## Log Analysis Guide

### Common Error Signatures

When reviewing logs, look for these patterns:

| Pattern | Meaning | Next Step |
|---------|---------|-----------|
| `Traceback (most recent call last)` | Python exception — read the last line for the actual error | Check the exception type and message at the bottom of the traceback |
| `ModuleNotFoundError: No module named '...'` | Missing dependency | Add the module to `requirements.txt` and rebuild |
| `ImportError: cannot import name '...'` | Wrong package version or API change | Check package version compatibility |
| `ConnectionRefusedError` / `ConnectionError` | Cannot reach external service | Verify the service URL, check if auth credentials are injected correctly |
| `401 Unauthorized` / `403 Forbidden` | Authentication/authorization failure | Check IAM token, service account permissions, or external API key |
| `OSError: [Errno 98] Address already in use` | Port conflict (usually 8080) | Ensure only one process binds to port 8080 |
| `MemoryError` / `Killed` | Out of memory | Scale up flavor or optimize memory usage |
| `TimeoutError` / `ReadTimeout` | External API or LLM call timed out | Increase timeout, check LLM endpoint health |
| `KeyError: '...'` | Missing expected field in payload/response | Check payload format matches what handler expects |
| `Health check failed` | `/health` endpoint not returning 200 | Verify `@app.ping` is defined and returns `PingStatus.HEALTHY` |

### Debugging Decision Tree

Use this flow to diagnose common issues:

```
Agent not responding?
├─ Check runtime status (/agentbase-deploy runtime get)
│  ├─ Status = FAILED → Check runtime logs (see runtime-logs above)
│  ├─ Status = CREATING → Wait, then re-check
│  └─ Status = ACTIVE → Check endpoint logs (see endpoint-logs above)
│     ├─ Logs show Python traceback → Fix the code error
│     ├─ Logs show "Health check failed" → Fix health endpoint
│     ├─ No recent logs → Check endpoint events (see events above) for infrastructure-level
│     │                    failures (image pull, out-of-memory, capacity), then metrics
│     └─ Logs look normal → Issue may be in request routing, check endpoint URL

Agent returns errors (4xx/5xx)?
├─ 500 Internal Server Error → Check endpoint logs for traceback (see endpoint-logs above)
├─ 502 Bad Gateway → Container crashed or not ready, check runtime logs (see runtime-logs above)
├─ 503 Service Unavailable → Container starting up or overloaded, check metrics (see metrics above)
└─ 401/403 → Check if agent's outbound auth is configured (/agentbase-identity)

Agent is slow?
├─ Check metrics for CPU/RAM (see metrics above)
│  ├─ CPU near limit → CPU-bound (e.g., stuck loop, heavy computation)
│  │  └─ Scale up flavor or optimize code
│  ├─ RAM near limit → Memory-bound (e.g., large model in memory, data leak)
│  │  └─ Scale up flavor or fix memory leak
│  └─ Both low → Bottleneck is external (LLM API, database, network)
│     └─ Check logs for slow external calls, add request timing
```

### Correlating Logs with Metrics

- **High CPU + normal RAM** → CPU-bound workload (tight loops, heavy computation, synchronous LLM calls)
- **High RAM + normal CPU** → Memory leak or large data structures (loading entire datasets, caching without limits)
- **Both high** → Resource exhaustion — scale up the flavor or optimize both code paths
- **Both low + slow responses** → External dependency bottleneck (LLM API latency, database queries, network timeouts)

### Log Filtering

Use server-side filtering when possible, and client-side techniques for finer control:

```bash
# Server-side: keyword search via --query
bash .claude/skills/agentbase/scripts/runtime.sh logs $RUNTIME_ID --from 0 --limit 100 --query "error"

# Server-side: time range filter
bash .claude/skills/agentbase/scripts/runtime.sh logs $RUNTIME_ID \
  --from 0 --limit 100 \
  --from-time "2026-03-13T00:00:00Z" --to-time "2026-03-13T12:00:00Z"

# Client-side: filter fetched results locally
LOGS=$(bash .claude/skills/agentbase/scripts/runtime.sh logs $RUNTIME_ID --from 0 --limit 100)
echo "$LOGS" | jq -r '.logs[].content' | grep -i "error\|traceback\|exception\|failed"

# Client-side: show only the last N lines
echo "$LOGS" | jq -r '.logs[].content' | tail -n 20

# Client-side: count errors
echo "$LOGS" | jq -r '.logs[].content' | grep -ci "error"
```

## Troubleshooting Guide

| Error | Cause | Fix |
|-------|-------|-----|
| Agent not responding | Runtime crashed or not started | Check runtime status (`/agentbase-deploy runtime get`), then check runtime logs for crash messages |
| 502/503 errors on endpoint | Container startup failure | Check endpoint logs for startup failures, verify health endpoint returns 200 |
| High latency | Resource saturation | Check metrics for CPU/RAM saturation, consider scaling up flavor or replicas |
| OOM kills | Memory spikes exceeding limit | Check metrics for memory spikes, increase flavor size |
| Image pull errors | Wrong URL or missing credentials | Verify `imageUrl` and registry credentials in runtime config |
| Container crash loop | Code error or missing dependencies | Check runtime logs for Python tracebacks or missing dependencies |

---

# Part 2: Status Dashboard

Show a unified dashboard of all AgentBase resources across services.

## How It Works

1. **Discover all resources** using `bash .claude/skills/agentbase/scripts/discovery.sh`
2. **Format into a dashboard** (see output format below)
3. **If any API call fails**, show that section as `Could not fetch (error details)` instead of crashing

---

## Output Format

Format the results into a readable dashboard. Example:

```
AgentBase Status Dashboard
==========================

IAM: Configured (client_id: abc...xyz)

Agent Identities (2):
  my-agent - "My first agent"
  test-bot - "Testing bot"

Auth Providers:
  API Keys (1): openai-prod (ACTIVE)
  Delegated (0): none
  OAuth2 (0): none

Runtimes (1):
  my-agent-rt (ACTIVE, v3, 1x1-general)
    DEFAULT: https://...

Memory (1):
  my-memory (2 strategies, 30d expiry)

AI Platform:
  API Keys (1): my-key (ACTIVE)

Container Registry:
  Repos (1): my-repo (private)
```

### Section Details

- **IAM**: Show masked client_id (first 3 + last 3 chars)
- **Agent Identities**: Name and description for each
- **Auth Providers**: Group by type (API Key, Delegated, OAuth2). Show name and status for each. Show "none" if empty.
- **Runtimes**: Name, status, description. For each runtime, list its endpoints with name, version, URL, and status. Fetch endpoints via `bash .claude/skills/agentbase/scripts/runtime.sh endpoints list $RUNTIME_ID`. (Note: runtime list DTO contains `id, name, description, status, statusReason, createdAt, updatedAt` — for flavor/version details, use `bash .claude/skills/agentbase/scripts/runtime.sh versions $RUNTIME_ID` which returns `version`, `imageUrl`, `flavorId`, `autoscaling` per version.)
- **Memory**: Name, number of strategies, event expiry duration
- **AI Platform**: API key names and status
- **Container Registry**: Repo names and access level (public/private)

### Error Handling

If any individual API call fails, display that section with the error instead of failing the whole dashboard:
```
Runtimes:
  Could not fetch (401 Unauthorized - token may be expired)
```

### --json Flag

If the user passes `--json`, output the raw JSON responses from all APIs as a single JSON object instead of the formatted dashboard:
```json
{
  "agentIdentities": { ... },
  "apiKeyProviders": { ... },
  "delegatedApiKeyProviders": { ... },
  "oauth2Providers": { ... },
  "runtimes": { ... },
  "memories": { ... },
  "aipApiKeys": { ... },
  "crRepository": { ... }
}
```

---

## Dashboard Pagination

Different services use different pagination:
- **Identity Service** (agent identities, auth providers): **0-indexed** (page=0 is first page)
- **Runtime Service**, **Memory Service**, **AI Platform**: **1-indexed** (page=1 is first page)

For the status dashboard, fetch the first page of each service with a reasonable size (e.g., size=10). If a service has more items than displayed, show the total count and offer to show more (e.g., "Showing 10 of 25 runtimes. Want to see more?").

---

## Instructions

1. Parse the user's argument to determine the operation (`runtime-logs`, `endpoint-logs`, `metrics`, `events`, `traces`, `dashboard`).
2. **For logs/metrics/events operations:**
   a. If a runtime ID is needed and not provided, list runtimes first (`bash .claude/skills/agentbase/scripts/runtime.sh list`) and ask the user to pick one.
   b. If an endpoint ID is needed, list endpoints for the runtime (`bash .claude/skills/agentbase/scripts/runtime.sh endpoints list $RUNTIME_ID`) and ask the user to pick one.
   c. For logs, default to `--from 0 --limit 100` to fetch the most recent entries. Use `--from` to paginate if more logs are needed (max `--from`: 5000, max `--limit`: 500). Use `--query` for keyword filtering and `--from-time`/`--to-time` for time range filtering when the user specifies these.
   d. Present log output in a readable format, highlighting errors and warnings. Each log entry has `timestamp` and `content` fields.
   e. For metrics, display CPU (`cpuCoresUsage`) and RAM (`memoryBytesUsage`, convert values to MB/GB) as time-series data points. Use `--from-time`/`--to-time` for historical ranges. To show usage as percentages, fetch available flavors via `bash .claude/skills/agentbase/scripts/runtime.sh flavors` (returns `id`, `name`, `cpu`, `ram` for each flavor), then match the runtime's `flavorId` to get CPU/RAM limits.
   f. For events, present each event as `lastTimestamp — message`, newest first. Match messages against the "Common event signatures" table to suggest a next step. Use this especially when an endpoint is stuck out of `ACTIVE` and logs are empty.
3. **For traces operation:** these are a passthrough to the tracing backend. Do NOT invent query param names — only pass `--param` keys the user supplies or that you sourced from the backend's docs/console. Return the backend's JSON response and parse per its schema.
4. **For dashboard operation:**
   a. Parse the user's argument for `--json` flag.
   b. Run `bash .claude/skills/agentbase/scripts/discovery.sh` (or `bash .claude/skills/agentbase/scripts/discovery.sh json` for raw JSON).
   c. Format the results as a dashboard (or raw JSON if `--json`).
   d. Display the dashboard to the user.
   e. After displaying, offer to drill into any section or show more items if pagination was truncated.
