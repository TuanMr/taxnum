# GreenNode AgentBase API Endpoints Reference

Centralized reference for all API base URLs used across AgentBase skills. Skills MUST read this file and use ONLY the domains listed below when constructing API URLs.

## DOMAIN VALIDATION — READ THIS FIRST

**ONLY the following API domains exist.** Any other domain is INVALID and must NOT be used:

| Valid Domain | Service |
|---|---|
| `agentbase.api.vngcloud.vn` | AgentBase (Identity, Runtime, Memory, Policy, MCP Gateway, Container Registry) |
| `aiplatform-hcm.api.vngcloud.vn` | AI Platform management (API keys, models) |
| `maas-llm-aiplatform-hcm.api.vngcloud.vn` | LLM inference endpoint (OpenAI-compatible) |
| `iam.api.vngcloud.vn` | IAM token endpoint |

**NEVER use domains that are NOT in the table above.** In particular:
- `maas.api.vngcloud.vn` — DOES NOT EXIST
- `aiplatform.api.vngcloud.vn` — DOES NOT EXIST (correct: `aiplatform-hcm.api.vngcloud.vn`)
- `agentbase-hcm.api.vngcloud.vn` — DOES NOT EXIST (correct: `agentbase.api.vngcloud.vn`)

Before constructing any curl command, verify the domain matches one of the valid domains above. Do NOT shorten, abbreviate, or modify domain names.

## AgentBase Services

| Service | Base URL | Pagination |
|---------|----------|------------|
| Identity | `https://agentbase.api.vngcloud.vn/identity/api/v1` | 0-indexed (`page=0` is first) |
| Runtime | `https://agentbase.api.vngcloud.vn/runtime` | 1-indexed (`page=1` is first) |
| Memory | `https://agentbase.api.vngcloud.vn/memory` | 1-indexed (`page=1` is first) |
| Policy | `https://agentbase.api.vngcloud.vn/policy/api/v1` | 1-indexed (`page=1` is first) |
| MCP Gateway | `https://agentbase.api.vngcloud.vn/gateway/api/v1` | 1-indexed (`page=1`, `pageSize` max 200); items in `.items`, paging in `.pagination` |

## AI Platform (AIP)

| Service | Base URL | Pagination |
|---------|----------|------------|
| Management API | `https://aiplatform-hcm.api.vngcloud.vn` | 1-indexed |
| LLM Endpoint (OpenAI-compatible) | `https://maas-llm-aiplatform-hcm.api.vngcloud.vn/v1` | N/A |

## Container Registry (CR)

| Service | Base URL | Pagination |
|---------|----------|------------|
| CR API | `https://agentbase.api.vngcloud.vn/cr/api/v1` | `GET /repository` is a single object (N/A); images/artifacts list: 1-indexed (`page=1`), items in `.data` |

## IAM

| Service | Base URL |
|---------|----------|
| Token Endpoint | `https://iam.api.vngcloud.vn/accounts-api/v2/auth/token` |

## Console URLs

| Service | Console URL |
|---------|-------------|
| IAM Service Accounts | `https://iam.console.vngcloud.vn/service-accounts` |
| IAM Policies | `https://iam.console.vngcloud.vn/policies` |
| Identity | `https://aiplatform.console.vngcloud.vn/access-control` |
| Runtime | `https://aiplatform.console.vngcloud.vn/agent-runtime?tab=runtime` |
| MCP Gateway | `https://aiplatform.console.vngcloud.vn/mcp-gateway` |
| Memory | `https://aiplatform.console.vngcloud.vn/memory` |
| AI Platform | `https://aiplatform.console.vngcloud.vn` |

## Response Shape Reference

API responses use **three different pagination formats** depending on the service:

### Identity Service (Spring-style)
```json
{
  "content": [ ... ],
  "totalElements": 42,
  "totalPages": 5,
  "number": 0,
  "size": 10
}
```
- `content` — array of items
- `totalElements` — total item count across all pages
- `totalPages` — total number of pages
- `number` — current page number (0-indexed)
- `size` — page size

### Runtime / Memory / AIP (GreenNode-style)
```json
{
  "listData": [ ... ],
  "totalItem": 42,
  "totalPage": 5,
  "page": 1,
  "pageSize": 10
}
```
- `listData` — array of items
- `totalItem` — total item count across all pages
- `totalPage` — total number of pages
- `page` — current page number (1-indexed)
- `pageSize` — page size

### MCP Gateway (nested-pagination)
```json
{
  "items": [ ... ],
  "pagination": {
    "page": 1,
    "pageSize": 50,
    "totalItems": 3,
    "hasMore": false
  }
}
```
- `items` — array of items
- `pagination.page` — current page number (1-indexed)
- `pagination.pageSize` — page size (max 200)
- `pagination.totalItems` — total item count across all pages
- `pagination.hasMore` — whether more pages remain

### Quick Reference

| Need | Identity Service | Runtime/Memory/AIP | MCP Gateway |
|------|-----------------|----------------------|-------------|
| Get items | `.content` | `.listData` | `.items` |
| Total count | `.totalElements` | `.totalItem` | `.pagination.totalItems` |
| Total pages | `.totalPages` | `.totalPage` | (use `.pagination.hasMore`) |
| First page param | `page=0` | `page=1` | `page=1` |
