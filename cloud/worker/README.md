# Koinly Self-Hosted Sync Worker

This is the optional backend used when a Koinly user wants multi-device synchronization.
The Worker runs on Cloudflare and stores synchronized finance data in the user's Turso database.

For the easiest setup, follow the beginner-friendly guide in the repository's main [`README.md`](../../README.md).

## Registration model

A fresh Worker accepts one owner account identified by a username. Email addresses are not used for authentication. Registration returns a one-time recovery key; after registration closes, additional devices use **Login** with the same username and password.

When administrator credentials are configured, registration is managed exclusively through `/profile`, including the first account. Existing accounts continue to sign in. This prevents public registration from reopening when an administrator deletes the last account.

## GitHub Actions deployment values

Use the eight-value checklist in [Section 4.1 of the main README](../../README.md#41-the-eight-values-you-will-create). Add all values during the same setup:

```text
CLOUDFLARE_NAME
CLOUDFLARE_API_TOKEN
CLOUDFLARE_ACCOUNT_ID
TURSO_DATABASE_URL
TURSO_AUTH_TOKEN
JWT_SECRET
ADMIN_USERNAME
ADMIN_PASSWORD
```

`CLOUDFLARE_NAME` may be a GitHub repository variable or secret. Save the other seven values as repository secrets. `JWT_SECRET` needs at least 32 characters. Choose a lowercase administrator username of 3–32 characters and a unique administrator password of 12–256 characters. Enter the password directly as `ADMIN_PASSWORD`; the deployment workflow creates the salted verifier automatically.

The original administrator password stays in GitHub's encrypted secret storage. The workflow sends only its salted verifier to Cloudflare, alongside the administrator username and the existing Turso/JWT settings. It does not print the password or write it to the generated deployment file. Ordinary account passwords are hashed by the Worker before database storage.

## Administration portal

**Existing self-hosted Worker owners MUST redeploy after updating.** The current deployment provisions the `SyncHub` SQLite-backed Durable Object used for realtime WebSocket sync notifications, while preserving existing Turso data and accounts. Apply the latest schema first (the GitHub workflow does this automatically). App updates alone do not update a deployed Worker.

Visit `https://<worker-name>.<account-subdomain>.workers.dev/profile`. For example: `https://koinly-test.sweets-4c4.workers.dev/profile`.

Complete the main setup once, then use the website:

1. Save all eight values from the main README's setup checklist in your GitHub repository.
2. Open **Actions > Deploy Self-Hosted Sync Worker > Run workflow**. Choose the branch containing the updated project, start the workflow, and wait for success.
3. Open your Worker's `/profile` address. Enter the username and password saved as `ADMIN_USERNAME` and `ADMIN_PASSWORD`, then select **Sign in**.
4. Select **+ Create account** to add a sync account. Fill in **Username**, **New password**, and **Confirm password**, then select **Create account**. The account holder can use **Login** in Koinly afterward.

Use **Change password** beside an account to reset its password. Use **Delete** to open the confirmation dialog; check the username before selecting **Delete account**. Use **Sign out** when finished. There is no separate hash-generation or administrator setup page.

For detailed steps, password changes, and troubleshooting, see [the main README's administration guide](../../README.md#worker-administration-portal).

Account lists expose only IDs, usernames, creation/update timestamps, and status, with an exact total and 50 accounts per page. **Invited** means no device has signed in; **Active** means at least one has signed in historically, not that a session is online. The administrator is separate and excluded from this count.

Creation and reset accept 8–256 character account passwords. Share new passwords privately. New account holders can create a recovery key in Koinly after login. A reset immediately invalidates old access/refresh sessions and the recovery key. Confirmed deletion atomically removes the account, sync records, devices, sessions, and Telegram backup settings; existing local copies and previously sent Telegram files remain.

Security details:

- Administrator authentication is required on the server for every account-management endpoint. An app bearer token cannot authorize portal access.
- Random one-hour sessions use `__Host-koinly-admin` cookies with `Secure`, `HttpOnly`, `SameSite=Strict`, and `Path=/`. Turso stores only keyed session hashes. Sign-out revokes the session; deployment refreshes the administrator verifier and invalidates portal sessions. Changing `JWT_SECRET` also invalidates them.
- Write requests require an exact matching `Origin` and `X-Profile-Request: 1`. No portal route enables cross-origin requests. HTML/API responses are private and not cached; pages use a nonce-based CSP, frame protection, and no external assets.
- Login is limited to eight attempts per Cloudflare-provided client IP and fifty globally per fifteen minutes, using atomic counters in Turso. Database errors fail closed and return a safe message.
- New passwords use random 16-byte salts and PBKDF2-HMAC-SHA256 (100,000 iterations). This uses the existing verifier's format and [Cloudflare's native Web Crypto](https://developers.cloudflare.com/workers/runtime-apis/web-crypto/), subject to the runtime's [PBKDF2 iteration limit](https://github.com/cloudflare/workerd/issues/1346). Legacy salted hashes remain usable; changing/resetting a password writes the new format. No password/hash is sent back in account API responses, embedded in HTML, or saved in browser storage.
- Existing access tokens remain compatible until their account's session version changes. Every authenticated app request checks that version and account existence. Resets increment it and revoke refresh tokens; deletion removes the account.

To recover administrator access, edit `ADMIN_PASSWORD` under GitHub's **Settings > Secrets and variables > Actions**, save a new password, and run **Deploy Self-Hosted Sync Worker** again. Keep `JWT_SECRET` unchanged for a routine password reset because it also protects other credentials and encrypted Worker data. If administrator configuration is missing, the portal blocks access while ordinary app sync continues to work.


## Administration API

All routes are under `/profile` so the existing app API's wildcard CORS never applies. Send JSON for POST requests, the same-origin administrator cookie, and `X-Profile-Request: 1` for writes.

| Method | Path | Purpose |
| --- | --- | --- |
| GET | `/profile` | Login page or authenticated dashboard |
| POST | `/profile/api/login` | `{ "username": "...", "password": "..." }`; creates cookie |
| POST | `/profile/api/logout` | Revokes session and clears cookie |
| GET | `/profile/api/accounts?page=1` | `{ total, page, pageSize, accounts }` |
| POST | `/profile/api/accounts` | `{ "username": "...", "password": "..." }`; creates account |
| POST | `/profile/api/accounts/:id/password` | `{ "password": "..." }`; resets password and revokes credentials |
| DELETE | `/profile/api/accounts/:id` | Permanently deletes account and related cloud data |

Errors return `{ "error": "..." }`: 400 invalid input, 401 invalid login/expired session, 403 rejected origin, 404 missing account, 409 duplicate username, 413 oversized request, 415 unsupported content type, 429 too many attempts, or 503 configuration/database failure. The UI presents errors and success messages and confirms deletion before sending it.

## Health check

Open:

```text
https://<worker-name>.<account-subdomain>.workers.dev/health
```

A ready Worker returns values equivalent to:

```json
{
  "ok": true,
  "service": "koinly-sync",
  "configured": true,
  "registrationMode": "first-user",
  "telegramBackupAvailable": true,
  "realtimeSyncAvailable": true,
  "databaseReachable": true,
  "schemaReady": true,
  "missingTables": []
}
```

## API

- `GET /`
- `GET /health`
- `POST /v1/auth/register`
- `POST /v1/auth/login`
- `POST /v1/auth/recover`
- `POST /v1/auth/recovery-key` (authenticated; rotates the key)
- `POST /v1/auth/refresh`
- `POST /v1/auth/logout`
- `GET /v1/sync/live` (authenticated WebSocket upgrade)
- `POST /v1/sync/initial`
- `POST /v1/sync/push`
- `POST /v1/sync/replace`
- `GET /v1/sync/pull?cursor=0&limit=100`
- `GET /v1/sync/status`
- `GET /v1/telegram-backup/settings`
- `POST /v1/telegram-backup/settings`
- `POST /v1/telegram-backup/test`
- `POST /v1/telegram-backup/send-now`

## Sync model

Clients write SQLite first and queue entity operations. The Worker stores the current entity state, deduplicates operation IDs, appends ordered changes for other devices, and enforces authenticated user scoping. After a successful write, the Worker signals the signed-in user's `SyncHub` Durable Object. Connected devices receive a lightweight `sync-change` WebSocket event and immediately perform the ordinary versioned incremental pull. The sending device is excluded from its own notification.

The WebSocket channel carries no finance payload; synchronized records still travel through the existing authenticated push/pull API. A periodic client pull remains as an eventual-consistency fallback if the live connection is unavailable.

The Flutter client uses merge-first synchronization. Full local reconciliation can upload the complete device snapshot, while cloud restore merges the remote state into the device instead of deleting local-only data.

`MAX_SYNC_BATCH_SIZE` defaults to `100`. `MAX_SYNC_REPLACE_SIZE` defaults to `25000`.

## Telegram `.koinlybackup`

`wrangler.self-hosted.toml` checks scheduled Telegram backups every five minutes. Users configure the optional Telegram bot from the authenticated Koinly app.

The Worker validates the destination, encrypts the bot token with AES-GCM, builds the `.koinlybackup` from synchronized entities, and refuses to send an empty finance backup.

For channels, the bot must be an administrator with permission to post messages.

## Troubleshooting

### Cloudflare error 1042

`TURSO_DATABASE_URL` must be a Turso `libsql://*.turso.io` URL. Do not point it at another Worker.

### Schema is not ready

On GitHub, open **Actions > Deploy Self-Hosted Sync Worker > Run workflow** and run it with the latest project files. The workflow applies the database update automatically. When it succeeds, reopen `/health` in your browser.

### Registration is closed

Create additional accounts from the `/profile` website using **+ Create account**. For another device using an existing account, select **Login** in Koinly. If an older deployment used email login, redeploy the latest Worker first; the schema migration converts the old email local-part into the username.


### Password recovery

New registrations return a recovery key once. The Worker stores only a keyed hash of that recovery key. `POST /v1/auth/recover` accepts the username, recovery key, and new password, rate-limits failed attempts, revokes existing refresh tokens after a successful reset, and issues a new session.

An authenticated user can call `POST /v1/auth/recovery-key` to rotate the recovery key. Only the newly generated key remains valid.

## Optional command-line setup

Use Node.js 22.13 or newer.

```bash
npm ci
npm run typecheck
npm test
```

Apply the schema:

```bash
export TURSO_DATABASE_URL='libsql://your-db.turso.io'
export TURSO_AUTH_TOKEN='your-token'
npm run schema:apply
```

For deployment, use **Actions > Deploy Self-Hosted Sync Worker > Run workflow** on GitHub. It applies the schema and prepares the administrator verifier automatically.

`schema.sql` can be applied again without deleting existing sync data. `scripts/apply-schema.mjs` migrates older email-based accounts and adds the recovery-key and session-version columns.

For advanced deployment integrations, `scripts/prepare-secrets.mjs` reads `ADMIN_PASSWORD` and the other required values from the process environment and emits a JSON secrets payload containing only the derived verifier. The GitHub workflow validates the inputs before applying the schema, writes this payload to a restricted temporary file, unsets the original password before calling Wrangler, and removes the file afterward. Do not invoke it in a way that displays the secrets payload in logs.
