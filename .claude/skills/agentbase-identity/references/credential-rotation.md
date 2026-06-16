# Credential Rotation

To rotate credentials stored in auth providers, use the update operations.

## Rotating a Static API Key

When an external API key needs to be rotated (e.g., OpenAI key renewal, compromised key):

1. Generate the new key from the external service (e.g., OpenAI dashboard)
2. Update the stored key:
   ```bash
   bash .claude/skills/agentbase/scripts/auth.sh apikey update --name openai-key --apikey-env NEW_OPENAI_KEY
   ```
3. The agent will immediately use the new key on subsequent requests — no redeployment needed

## Rotating OAuth2 Client Credentials

When OAuth2 client credentials need rotation:

1. Generate new credentials from the OAuth2 provider (e.g., Google Cloud Console)
2. Update the provider (the script automatically fetches current values and merges with your updates):
   ```bash
   bash .claude/skills/agentbase/scripts/auth.sh oauth2 update --name google-oauth --client-id "new-xxx.apps.googleusercontent.com" --client-secret-env GOOGLE_CLIENT_SECRET
   ```
   Note: The PUT API requires all 4 fields (clientId, clientSecret, authorizationUrl, tokenUrl). The script auto-fetches the existing provider and merges your updates with the current values, so you only need to pass the fields that changed.
3. Existing user authorizations may need to be re-established depending on the OAuth2 provider

## Rotating Delegated API Keys

Delegated providers have no stored credentials to rotate — end-users manage their own keys. To force users to re-authorize, delete and recreate the delegated provider.

## Rotating Platform IAM Credentials

To rotate the IAM service account credentials used for platform API access:

1. Go to https://iam.console.vngcloud.vn/service-accounts
2. Click your service account → **"Security credentials"** tab → **"Reset"**
3. **Warning**: The old secret is invalidated immediately — update all systems using it
4. Update `GREENNODE_CLIENT_ID`/`GREENNODE_CLIENT_SECRET` in environment variables or `.greennode.json`
5. For deployed runtimes, use `PATCH /agent-runtimes/{id}/reset-service-account` (see `/agentbase-deploy runtime`) to regenerate the runtime's auto-managed credentials
