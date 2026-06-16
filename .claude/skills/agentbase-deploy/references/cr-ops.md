# Container Registry (CR) — Operations Reference

Operational workflows for the AgentBase-managed Container Registry.

All operations use the CR script: `bash .claude/skills/agentbase/scripts/cr.sh`

The script handles IAM token acquisition/refresh, response redaction (the `secret` field is redacted by default in `credentials get/reset`), and error handling.

For request/response schemas, see `cr-api.md`.

**Service model recap:**
- Single pre-provisioned repo per user. No create/delete repo APIs.
- Single credential pair (`username` + `secret`) per user. Rotate via `credentials reset`.
- Image push URL template: `{registryUrl}/{repoName}/{imageName}:{tag}` — read both fields from `cr.sh repo get`.

---

## 1. First-Time Setup (Push Your First Image)

Use this when you have a built Docker image and want to push it to the managed registry. The credentials never touch disk — they are fetched in-memory and piped to `docker login --password-stdin`.

```bash
# 1. Inspect the repo to find registryUrl and name
bash .claude/skills/agentbase/scripts/cr.sh repo get

# Example response:
# { "name": "my-repo", "registryUrl": "vcr.vngcloud.vn", ... }

# 2. Fetch credentials and docker-login in one shot (no file written).
bash .claude/skills/agentbase/scripts/cr.sh credentials docker-login

# 3. Tag and push (use the values from step 1)
docker tag <local-image>:<tag> vcr.vngcloud.vn/my-repo/<image-name>:<tag>
docker push vcr.vngcloud.vn/my-repo/<image-name>:<tag>
```

`credentials docker-login` calls `GET /registry-credential` to retrieve the current secret. Pass `--reset` to rotate first (`PATCH /registry-credential/secret`) — useful if you suspect the existing secret was leaked.

---

## 2. Inspect the Repository

```bash
bash .claude/skills/agentbase/scripts/cr.sh repo get
```

Response fields you'll most often use:
- `name` — the repo segment of every image URL.
- `registryUrl` — the Docker host (e.g., `vcr.vngcloud.vn`).
- `quotaUsed` / `quotaLimit` — bytes; check before pushing large images.
- `imageCount` — quick sanity check.

---

## 3. Managing Credentials

### Get current credentials
```bash
# Username only (secret is redacted by default)
bash .claude/skills/agentbase/scripts/cr.sh credentials get

# Show the secret in plaintext (only when you need it, e.g. for manual docker login)
REDACT_FIELDS= bash .claude/skills/agentbase/scripts/cr.sh credentials get
```

### Rotate (reset) credentials
```bash
bash .claude/skills/agentbase/scripts/cr.sh credentials reset
```

**Effect:** the old secret is invalidated immediately. Anywhere it was used (Docker logins on dev machines, runtime `imageAuth`, CI/CD pipelines, K8s pull secrets) must be re-issued.

Recommended pattern: combine with `docker-login` to rotate AND re-login in one step:

```bash
bash .claude/skills/agentbase/scripts/cr.sh credentials docker-login --reset
```

This rotates the secret and pipes the new one into `docker login --password-stdin`. Nothing is written to disk.

---

## 4. Listing & Deleting Images

### List images
```bash
# All images, paginated
bash .claude/skills/agentbase/scripts/cr.sh images list --page 1 --size 50

# Filter by name substring
bash .claude/skills/agentbase/scripts/cr.sh images list --name myagent
```

Response includes per-image: `name`, `updateTime`, `pullCount`, `artifactCount`. Use `totalPage` to know whether to paginate further.

### Delete an image (and ALL its artifacts)
```bash
bash .claude/skills/agentbase/scripts/cr.sh images delete --name myagent
```

**Irreversible.** Before deleting, confirm with the user:
- The image name is correct.
- They understand all artifacts (tags + digests) under this name will be removed.
- No live runtime is currently pulling from this image.

---

## 5. Listing & Deleting Artifacts

An artifact is one digest within an image. Typical reason to operate at this level: prune old versions while keeping the current tag.

### List artifacts for an image
```bash
bash .claude/skills/agentbase/scripts/cr.sh artifacts list --image myagent --page 1 --size 50
```

Each artifact entry includes:
- `digest` — the immutable artifact ID; use this to delete.
- `tags[]` — human-readable tags pointing to this digest.
- `size`, `pushTime`, `pullTime` — for sizing & cleanup decisions.

### Filter to a specific digest
```bash
bash .claude/skills/agentbase/scripts/cr.sh artifacts list --image myagent --digest sha256:abc123...
```

### Delete an artifact
```bash
bash .claude/skills/agentbase/scripts/cr.sh artifacts delete \
  --image myagent --digest sha256:abc123...
```

**Irreversible.** The image itself remains if other artifacts exist; only this digest is removed.

---

## 6. Cleanup Workflow (prune old artifacts)

Common scenario: keep the current `latest` artifact, delete everything older.

```bash
# 1. List all artifacts for the image
bash .claude/skills/agentbase/scripts/cr.sh artifacts list --image myagent --size 100

# 2. Identify the digest of the "latest" tag (read from the listed tags[])
#    and the digests to remove.

# 3. Delete each old digest
bash .claude/skills/agentbase/scripts/cr.sh artifacts delete \
  --image myagent --digest sha256:olddigest1
bash .claude/skills/agentbase/scripts/cr.sh artifacts delete \
  --image myagent --digest sha256:olddigest2
```

Always present the deletion plan to the user and ask for explicit confirmation before each batch.

---

## 7. Integration with Deploy Flow

No credentials file is needed. `cr.sh credentials docker-login` handles local `docker push`, and `runtime.sh create/update --from-cr` fetches credentials inline when creating the runtime so it can pull the private image.

Typical full deploy path:

```bash
# Build, login to CR, push (credentials piped in memory; nothing on disk)
docker build --platform linux/amd64 -t vcr.vngcloud.vn/<repoName>/<image>:<tag> .
bash .claude/skills/agentbase/scripts/cr.sh credentials docker-login
docker push vcr.vngcloud.vn/<repoName>/<image>:<tag>

# Deploy — runtime fetches CR credentials at create time and embeds them in imageAuth
bash .claude/skills/agentbase/scripts/runtime.sh create \
  --name myagent \
  --image vcr.vngcloud.vn/<repoName>/<image>:<tag> \
  --flavor 1x1-general \
  --env-file .env \
  --from-cr
```

If you rotate the secret later (`cr.sh credentials reset`), re-run `cr.sh credentials docker-login` to refresh your local Docker session, and update existing runtimes with `runtime.sh update <id> ... --from-cr` so their cached `imageAuth` reflects the new secret. The legacy `--registry-credentials-file` flag still works for non-CR registries (Docker Hub, GHCR, etc.).

---

## 8. Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `401 Unauthorized` on `cr.sh` calls | IAM token missing/expired | Run `bash .claude/skills/agentbase/scripts/check_credentials.sh iam` |
| `docker push` returns `unauthorized` after a `credentials reset` | Local Docker still cached the old secret | Re-run `cr.sh credentials docker-login` |
| Runtime fails to pull image after rotating | Runtime still has old `imageAuth` | Refresh the runtime: `runtime.sh update $RUNTIME_ID ... --from-cr` |
| `400 Bad Request` on `artifacts list` | Missing `--image` flag | `imageName` query param is required by the API |
| `404 Not Found` on `images delete` | Wrong `--name` (case-sensitive) | List first with `images list` to confirm the exact name |
| Push fails with `denied: requested access to the resource is denied` | Image tagged with wrong repo name | Re-tag using `{registryUrl}/{repoName}/<image>:<tag>` from `repo get` |
| Quota exceeded on push | `quotaUsed` near `quotaLimit` | Prune old artifacts (Section 6) or contact platform support to raise the quota |
