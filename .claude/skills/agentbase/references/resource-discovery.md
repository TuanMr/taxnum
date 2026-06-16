# Resource Discovery Reference

Shared reference for discovering all AgentBase resources across services. Used by `/agentbase-monitor` (dashboard) and `/agentbase-teardown`.

## Discovery

Run the discovery script to fetch resources across all services:

```bash
bash .claude/skills/agentbase/scripts/discovery.sh
```

For JSON output, use `bash .claude/skills/agentbase/scripts/discovery.sh json`

## Service Summary

| Service | API | Base URL | Pagination | Response Items Field |
|---------|-----|----------|------------|---------------------|
| Agent Identities | `GET /api/v1/agent-identities?page=0&size=100` | `https://agentbase.api.vngcloud.vn/identity` | 0-indexed | `.content` |
| API Key Providers | `GET /api/v1/outbound-auth/api-key-providers?page=0&size=100` | `https://agentbase.api.vngcloud.vn/identity` | 0-indexed | `.content` |
| Delegated Providers | `GET /api/v1/outbound-auth/delegated-api-key-providers?page=0&size=100` | `https://agentbase.api.vngcloud.vn/identity` | 0-indexed | `.content` |
| OAuth2 Providers | `GET /api/v1/outbound-auth/oauth2-providers?page=0&size=100` | `https://agentbase.api.vngcloud.vn/identity` | 0-indexed | `.content` |
| Runtimes | `GET /agent-runtimes?page=1&size=100` | `https://agentbase.api.vngcloud.vn/runtime` | 1-indexed | `.listData` |
| Memories | `GET /memories?page=1&size=100` | `https://agentbase.api.vngcloud.vn/memory` | 1-indexed | `.listData` |
| AIP API Keys | `GET /v1/api-keys?page=1&size=100` | `https://aiplatform-hcm.api.vngcloud.vn` | 1-indexed | `.listData` |
| CR Repository | `GET /repository` | `https://agentbase.api.vngcloud.vn/cr/api/v1` | N/A (single repo) | `[.]` (bare object) |

## Error Handling

If any individual API call fails, handle that section as an error rather than failing the entire discovery. Show `Could not fetch (error details)` for the failed section.

## Response Shape

See `references/endpoints.md` for full response shape documentation (Identity uses Spring-style `{content, totalElements}`, other services use GreenNode-style `{listData, totalItem}`).
