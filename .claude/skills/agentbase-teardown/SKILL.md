---
name: agentbase-teardown
description: "Clean up and remove all platform resources for an agent project. Tears down runtime, identity, auth, memory, registry, and API keys in one go. Use when user wants to tear down, decommission, remove everything, start over, or delete all resources for an agent. DO NOT use for deleting a single resource — use /agentbase-deploy for runtimes, /agentbase-identity for identity/auth, /agentbase-memory for memory. Only use when intent is to remove ALL or MOST resources."
---

# AgentBase Teardown

Guided cleanup of all AgentBase resources for a project or agent.

## Authentication

Read the shared auth setup reference at `/agentbase` skill's `references/auth-setup.md` for full IAM credential configuration. In brief: run `bash .claude/skills/agentbase/scripts/check_credentials.sh iam` to verify credentials are configured. **NEVER read `.greennode.json` or `.env` directly** — always use the helper scripts. If `check_credentials.sh iam` returns MISSING, **STOP — you MUST read** the **"If Credentials Are Not Found"** section in `/agentbase` skill's `references/auth-setup.md` and follow it exactly. Do NOT skip this or provide your own credential setup instructions.

---

## Interaction Guidelines

- **Never assume API response structure** — always inspect the actual response first before extracting or filtering data. Do not guess field names.
- **ALWAYS show full deletion plan before executing** — never delete anything without showing the user exactly what will be removed
- **ALWAYS require explicit confirmation (HARD GATE)** — the user must respond with an explicit confirmation keyword (`yes`, `confirm`, `ok`, `approve`, `proceed`, `go ahead`, `do it`, `lgtm`, or equivalent affirmative) before any deletion begins. If the user responds with ANYTHING ELSE (deselecting items, questions, adjustments, or ambiguous text), treat it as additional input — update the plan and re-present for confirmation again. NEVER interpret a non-confirmation response as approval
- **Support --dry-run** — if the user passes `--dry-run`, show the plan only and do not execute any deletions
- **Let user deselect items** — after presenting the plan, let the user choose which items to keep (e.g., "keep the AIP key, delete everything else")
- **Warn about shared resources** — if a resource may be used by other agents (e.g., an AIP API key, an auth provider), explicitly warn the user (e.g., "This AIP key may be used by other agents")
- **Show progress during deletion** — report each deletion as it completes
- **Always read full API response body** — when calling platform APIs, capture and read the full JSON response (not just status codes). This avoids misidentifying field names or data structures, ensures correct field extraction, and enables better error handling and debugging.

---

## How It Works

### Step 1: Identify the Project

Determine which project/agent to tear down:
- If a project name is provided as argument, use it
- If `.agentbase-state.json` exists in the current directory, read the agent/project name from it
- Otherwise, ask the user which agent/project to tear down

### Step 2: Discover Related Resources

Discover all resources matching the project name:

```bash
bash .claude/skills/agentbase/scripts/discovery.sh json
```

This returns JSON with all resources across all services. Parse the output to find resources matching the project name.

**Resource matching priority**:
1. **Exact resource IDs** from `.agentbase-state.json` or `.greennode.json` (preferred — most precise)
2. **Prefix matching** — look for resources whose name starts with the project name (case-insensitive). For example, project "my-agent" matches "my-agent-identity" and "my-agent-key", but NOT "test-my-agent".
3. **Exact name match** — if prefix matching returns no results, try exact match on the project name itself.

> **Warning**: Always show exact resource IDs and full names in the deletion plan so the user can verify which resources will be affected. If matching finds resources that may belong to other projects, explicitly warn the user and ask them to confirm each resource individually.

### Step 3: Present Deletion Plan

Show the user a numbered plan of what will be deleted:

```
Teardown Plan for "my-agent":
  1. Delete runtime endpoints (2 endpoints)
  2. Delete runtime "my-agent-rt" (v3)
  3. Delete auth provider "openai-key" (API Key)
  4. Delete agent identity "my-agent"
  5. Delete memory "my-agent-memory"
  6. Delete CR images for this project (3 images, all artifacts)
  7. Delete AIP API key "my-agent-key" (shared resource)

All deletions are IRREVERSIBLE.
Proceed with all? Or type numbers to exclude (e.g., "skip 6,7"):
```

If no related resources are found, tell the user and stop.

### Step 4: Get User Confirmation

Wait for the user to:
- Confirm all deletions
- Deselect specific items (e.g., "skip 7" or "keep the AIP key")
- Cancel entirely

Do NOT proceed without explicit confirmation.

### Step 5: Execute Deletions in Dependency Order

Delete in this specific order to avoid dependency errors. If any script call returns an auth error (401/403) during the teardown sequence, re-authenticate with `bash .claude/skills/agentbase/scripts/get_token.sh --force` and retry the failed call once. If the retry also fails, report the error and continue with the next deletion.

**Phase 1 — Runtime endpoints** (MUST run before Phase 2):
> **Why order matters**: The API rejects runtime deletion if custom endpoints still exist. You must delete all non-DEFAULT endpoints before deleting the runtime.

```bash
# List endpoints for each runtime
bash .claude/skills/agentbase/scripts/runtime.sh endpoints list $RUNTIME_ID

# Delete each non-DEFAULT endpoint
bash .claude/skills/agentbase/scripts/runtime.sh endpoints delete $RUNTIME_ID $ENDPOINT_ID
```

**Phase 2 — Runtimes** (only after all custom endpoints are deleted):
```bash
bash .claude/skills/agentbase/scripts/runtime.sh delete $RUNTIME_ID
```

**Phase 3 — Auth providers** (API Key, Delegated, OAuth2):
```bash
# API Key providers
bash .claude/skills/agentbase/scripts/auth.sh apikey delete --name $NAME

# Delegated providers
bash .claude/skills/agentbase/scripts/auth.sh delegated delete --name $NAME

# OAuth2 providers
bash .claude/skills/agentbase/scripts/auth.sh oauth2 delete --name $NAME
```

**Phase 4 — Agent identity:**
```bash
bash .claude/skills/agentbase/scripts/identity.sh delete $NAME
```

**Phase 5 — Memory:**
```bash
bash .claude/skills/agentbase/scripts/memory.sh delete $MEMORY_ID
```

**Phase 6 — Container Registry images:**
> **Important**: Each user has **one pre-provisioned repository** that cannot be deleted. Teardown only removes images (and their artifacts) belonging to the project. List images first, filter by project name, then delete each one.

```bash
# Step 1: List images, filter by project name substring (paginate if totalPage > 1)
PAGE=1
while true; do
  RESULT=$(bash .claude/skills/agentbase/scripts/cr.sh images list --name $PROJECT_NAME --page $PAGE --size 100)
  # For each image in $RESULT.data[].name:
  #   bash .claude/skills/agentbase/scripts/cr.sh images delete --name $IMAGE_NAME
  # (image delete cascades to all artifacts/tags under that image.)
  TOTAL_PAGE=$(echo "$RESULT" | jq '.totalPage // 1')
  [ "$PAGE" -ge "$TOTAL_PAGE" ] && break
  PAGE=$((PAGE + 1))
done

# Step 2: Verify project images are gone
bash .claude/skills/agentbase/scripts/cr.sh images list --name $PROJECT_NAME
```

**Phase 7 — AIP API keys** (optional, may be shared):
```bash
bash .claude/skills/agentbase/scripts/aip.sh api-keys delete $KEY_NAME
```
The `aip.sh api-keys delete` command sends the DELETE request and returns immediately. Poll with `aip.sh api-keys get $KEY_NAME` until you get a 404 to confirm deletion.

### Step 6: Report Results

Show a summary of what was deleted and any errors:

```
Teardown Results for "my-agent":
  Deleted runtime endpoints (2)
  Deleted runtime "my-agent-rt"
  Deleted auth provider "openai-key"
  Deleted agent identity "my-agent"
  Deleted memory "my-agent-memory"
  Skipped CR images for "my-agent" (user chose to keep)
  Failed to delete AIP key "my-agent-key" (403 Forbidden)

Teardown finished. 5 of 7 resources removed. 2 failed — see errors above.
```

### Step 7: Clean Up Local State

If `.agentbase-state.json` exists in the current directory, **reset the `wizard_step` to 0** and clear resource IDs that were deleted (e.g., `runtime_id`, `memory_id`, `agent_identity`, `aip_key_name`, `cr_repo_name`). This prevents `/agentbase-wizard resume` from trying to resume with stale references to deleted resources. Only clear fields for resources that were actually deleted — keep fields for resources the user chose to skip/keep.

If `.agentbase/` directory exists, offer to remove it:
```
Found local AgentBase files:
  - .agentbase-state.json (wizard state — will be reset)
  - .agentbase/ (token cache, temp files)
Reset wizard state and remove cache? (y/n)
```
If file operations fail (e.g., permission denied), report the specific error and suggest the user handle them manually.

---

## Troubleshooting

| Error | Cause | Fix |
|-------|-------|-----|
| Runtime deletion fails (400) | Custom endpoints still exist | Delete all non-DEFAULT endpoints first, then retry runtime deletion (see Phase 1 → Phase 2 order) |
| CR image delete fails (404) | Wrong `--name` (case-sensitive) or image already gone | List first with `cr.sh images list --name $PROJECT_NAME` to confirm exact names |
| 401 Unauthorized mid-teardown | IAM token expired during long teardown | Re-authenticate (`get_token.sh --force`) and retry the failed deletion |
| Resource belongs to another project | Name-based matching too broad (e.g., project "test" matches "api-test") | Always verify resource IDs in the deletion plan. Deselect items that don't belong to the target project |
| Identity deletion fails (404/500) | Identity name incorrect or already deleted | Verify identity name with `identity.sh list` before retrying |
| Memory deletion fails | Memory ID incorrect or already deleted | Verify memory ID with `memory.sh list` before retrying |

---

## Instructions

1. Parse the user's argument for project name and `--dry-run` flag.
2. Authenticate (see Authentication section).
3. Identify the project (argument, `.agentbase-state.json`, or ask user).
4. Discover all related resources using `bash .claude/skills/agentbase/scripts/discovery.sh json`.
5. Present the deletion plan with numbered items.
6. If `--dry-run`, stop after showing the plan.
7. Wait for user confirmation (allow deselecting items).
8. Execute deletions in dependency order using the script commands, reporting progress.
9. Show final summary.
10. Offer to clean up `.agentbase-state.json` and `.agentbase/` directory if present.
