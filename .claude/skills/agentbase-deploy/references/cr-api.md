# Container Registry (CR) — API Reference

Base URL: `https://agentbase.api.vngcloud.vn/cr/api/v1`

All endpoints require `Authorization: Bearer {iam_access_token}` header (same IAM auth as other AgentBase services).

**Service model:**
- Each user has **one pre-provisioned repository** — no create/delete repo APIs.
- Each user has **one credential pair** (`username` + `secret`) — no robot accounts.
- Pagination is **1-based** (`page=1` is the first page; default `size=10`).
- The underlying registry host is `vcr.vngcloud.vn`. Image push URL template: `{registryUrl}/{repoName}/{imageName}:{tag}`.

---

## 1. Repository

### Get Repository Info
```
GET /repository
```

Response (`RepositoryResponse`):
```json
{
  "name": "my-repo",
  "registryUrl": "vcr.vngcloud.vn",
  "createdAt": "2026-01-15T08:00:00Z",
  "imageCount": 5,
  "quotaUsed": 311926433,
  "quotaLimit": 21474836480
}
```

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Repository name (use this as `{repoName}` in image URL) |
| `registryUrl` | string | Docker registry host to push to |
| `createdAt` | string (ISO 8601) | Provisioning time |
| `imageCount` | integer | Number of images stored |
| `quotaUsed` | integer | Bytes currently used |
| `quotaLimit` | integer | Quota cap in bytes |

---

## 2. Registry Credentials

Credentials for `docker login`. The `secret` is the Docker password.

### Get Credentials
```
GET /registry-credential
```

Response (`RegistryCredentialInfo`):
```json
{
  "username": "u-123456",
  "secret": "abcdef0123456789"
}
```

### Reset Credentials Secret
```
PATCH /registry-credential/secret
```

Rotates the secret. Returns the **new** `RegistryCredentialInfo`. Old secret is immediately invalidated — any cached Docker logins must be re-issued.

---

## 3. Images

An image is a logical name in the repo (e.g. `myagent`). It holds one or more artifacts (tags/digests).

### List Images
```
GET /repository/images?imageName={name}&page={n}&size={n}
```

Query params:
- `imageName` (string, optional) — filter by name substring
- `page` (integer, default 1)
- `size` (integer, default 10)

Response (`ImagePage`):
```json
{
  "data": [
    {
      "name": "myagent",
      "updateTime": "2026-05-01T12:00:00Z",
      "pullCount": 42,
      "artifactCount": 3
    }
  ],
  "page": 1,
  "pageSize": 10,
  "totalItem": 1,
  "totalPage": 1
}
```

### Delete Image
```
DELETE /repository/images?imageName={name}
```

Deletes the image **and all its artifacts**. Irreversible.

Query params:
- `imageName` (string, required)

Returns `204 No Content` on success.

---

## 4. Artifacts

An artifact is a specific manifest within an image (one digest, zero-or-more tags).

### List Artifacts
```
GET /repository/artifacts?imageName={name}&digest={digest}&page={n}&size={n}
```

Query params:
- `imageName` (string, required)
- `digest` (string, optional) — filter to a specific digest
- `page` (integer, default 1)
- `size` (integer, default 10)

Response (`ArtifactPage`):
```json
{
  "data": [
    {
      "digest": "sha256:abc123...",
      "type": "IMAGE",
      "size": 12345678,
      "pushTime": "2026-05-01T12:00:00Z",
      "pullTime": "2026-05-02T09:30:00Z",
      "tags": [
        { "name": "v20260501", "pushTime": "...", "pullTime": "..." },
        { "name": "latest",    "pushTime": "...", "pullTime": "..." }
      ]
    }
  ],
  "page": 1,
  "pageSize": 10,
  "totalItem": 1,
  "totalPage": 1
}
```

### Delete Artifact
```
DELETE /repository/artifacts?imageName={name}&digest={digest}
```

Deletes a single artifact (one digest) within the image. The image itself remains if other artifacts exist.

Query params:
- `imageName` (string, required)
- `digest` (string, required)

Returns `204 No Content` on success.

---

## 5. Error Responses

All error responses use `ErrorBody`:

```json
{
  "error": {
    "code": "NOT_FOUND",
    "message": "Image not found",
    "requestId": "..."
  }
}
```

| HTTP | Meaning | Common cause |
|------|---------|--------------|
| 400 | Bad Request | Missing/invalid query param (e.g. `imageName` not provided for artifacts list) |
| 401 | Unauthorized | Missing or expired IAM token |
| 404 | Not Found | Image or artifact does not exist |
| 500 | Internal Server Error | Backend issue — retry or contact support |
| 502 | Bad Gateway | Upstream registry unreachable |

---

## 6. Data Models

| Model | Fields |
|-------|--------|
| `RepositoryResponse` | `name`, `registryUrl`, `createdAt`, `imageCount`, `quotaUsed`, `quotaLimit` |
| `RegistryCredentialInfo` | `username`, `secret` |
| `ImageResponse` | `name`, `updateTime`, `pullCount`, `artifactCount` |
| `ArtifactResponse` | `digest`, `type`, `size`, `pushTime`, `pullTime`, `tags[]` |
| `TagResponse` | `name`, `pushTime`, `pullTime` |
| `ImagePage` / `ArtifactPage` | `data[]`, `page`, `pageSize`, `totalItem`, `totalPage` |
| `ErrorBody` | `error.code`, `error.message`, `error.requestId` |
