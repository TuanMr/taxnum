# AgentBase Authentication Setup

## Credential Discovery

**NEVER read credential files (`.greennode.json`, `.env`) directly.** Always use the provided helper scripts which read credentials internally and keep secret values out of the LLM context.

To check if IAM credentials are configured, run:

```bash
bash .claude/skills/agentbase/scripts/check_credentials.sh iam
```

This checks environment variables (`GREENNODE_CLIENT_ID`, `GREENNODE_CLIENT_SECRET`) and `.greennode.json` without exposing their values. It returns `OK` or `MISSING` with guidance.

## If Credentials Are Not Found

Present the user with three numbered options and wait for their explicit choice before proceeding:

1. **Auto create IAM Service Account** — **you MUST read and follow** the "Automated IAM Service Account Setup" section in the `/agentbase` skill's SKILL.md. Do NOT improvise the setup flow.
2. **Import from a credentials file** — user provides a path to a JSON file containing `client_id` and `client_secret`:
   ```bash
   bash .claude/skills/agentbase/scripts/save_iam_credentials.sh --from-file /path/to/credentials.json
   ```
3. **I already have credentials / create manually** — user provides `client_id` and `client_secret` values. Save using `save_iam_credentials.sh` with `--secret-stdin` (never pass secret on command line):
   ```bash
   echo '<client_secret>' | bash .claude/skills/agentbase/scripts/save_iam_credentials.sh \
     --client-id "<client_id>" --secret-stdin
   ```

If the user chooses option 1, confirm once more before starting the setup flow.

## Token Fetching (with Caching)

The SDK auto-loads credentials from env vars or `.greennode.json`. For curl-based API calls, use the shared `get_token.sh` script.

### Token script — `scripts/get_token.sh`

A standalone script at `.claude/skills/agentbase/scripts/get_token.sh` that handles credential loading, token caching, and JWT-based expiry validation. Credentials are read internally by the script — they never appear in stdout. No function definition needed — just call it.

### Usage

```bash
TOKEN=$(bash .claude/skills/agentbase/scripts/get_token.sh)
curl -s -X GET "https://agentbase.api.vngcloud.vn/..." \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json"
```

### Handling 401 (token expired)

Force a fresh token (bypasses cache):

```bash
TOKEN=$(bash .claude/skills/agentbase/scripts/get_token.sh --force)
```

### Rules for token management

- **ALWAYS** use `TOKEN=$(bash .claude/skills/agentbase/scripts/get_token.sh)` before making API calls. **NEVER** fetch a token with inline curl.
- The cache file `.agentbase/token_cache` is shared across all skills — a token fetched by one skill is reused by others.
- On **401** responses: re-run with `--force` to bypass cache.
- Token expiry is determined by decoding the JWT `exp` claim — no hardcoded TTL.

## Token Usage

Include the token in the `Authorization` header for all API calls:

```
Authorization: Bearer $TOKEN
```

## Credential Security Rules

- **NEVER read `.greennode.json` or `.env` directly** — always use the helper scripts in `.claude/skills/agentbase/scripts/`.
- **NEVER display passwords or secret values** in plan summaries or confirmation messages. Show usernames but mask passwords as `********`.
- **NEVER pass secrets on the command line** — always use `--password-stdin`/`--value-stdin` (pipe via stdin) or `--password-file`/`--value-file` (read from file). This applies to all credential types: Docker passwords, API keys, tokens, and any other secrets.
- The `.agentbase/` directory holds cached/temp files. It should be added to `.gitignore` and `.dockerignore`.

## Available Helper Scripts

| Script | Purpose |
|--------|---------|
| `check_credentials.sh iam` | Check if IAM credentials exist (no values revealed) |
| `check_credentials.sh llm` | Check if LLM API key exists (`LLM_API_KEY` or `AIP_API_KEY`, no values revealed) |
| `check_env.sh [directory]` | Scan Python files for `os.environ.get`/`os.getenv` references, check which vars are present/missing in `.env` (no values revealed). Returns JSON with `required`, `present`, `missing` arrays |
| `check_credentials.sh registry <path>` | Check if Docker registry credentials exist (no values revealed) |
| `get_token.sh` | Get IAM token (reads credentials internally, caches in `.agentbase/token_cache`) |
| `prepare_image_auth.sh` | Build imageAuth JSON for private registries (writes to `.agentbase/imageauth.json`, no secrets on stdout) |
| `docker_login.sh` | Docker login using saved credentials (uses `--password-stdin`) |
| `save_iam_credentials.sh` | Save IAM credentials to `.greennode.json` (supports `--secret-stdin`, `--secret-file`, `--from-file` for import). Auto-adds to `.gitignore`/`.dockerignore` |
| `save_registry_credentials.sh` | Save Docker registry credentials to a user-specified file via `--output-file <path>` (supports `--password-stdin`, `--password-file`) |
| `save_env_var.sh` | Save secrets/config to `.env` (supports `--value-stdin`, `--value-file`). Auto-adds `.env` to `.gitignore`/`.dockerignore` |
| `redact_response.sh` | Pipe API responses through this to redact sensitive fields (`secretKey`, `key`, `password`). Saves raw response to `.agentbase/last_response.json`, outputs redacted version |
