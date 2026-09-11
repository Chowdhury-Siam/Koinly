# Koinly Self-Hosted Sync Worker

This is the optional backend used when a Koinly user wants multi-device synchronization.
The Worker runs on Cloudflare and stores synchronized finance data in the user's Turso database.

For the easiest setup, follow the beginner-friendly guide in the repository's main [`README.md`](../../README.md).

## Registration model

A fresh Worker accepts one owner account identified by a username. Email addresses are not used for authentication. Registration returns a one-time recovery key; after registration closes, additional devices use **Login** with the same username and password.

When administrator credentials are configured, registration is managed exclusively through `/profile`, including the first account. Existing accounts continue to sign in. This prevents public registration from reopening when an administrator deletes the last account.

## GitHub Actions deployment values

The self-hosted deployment workflow expects these exact GitHub names:

```text
CLOUDFLARE_NAME
CLOUDFLARE_API_TOKEN
CLOUDFLARE_ACCOUNT_ID
TURSO_DATABASE_URL
TURSO_AUTH_TOKEN
JWT_SECRET
```

`CLOUDFLARE_NAME` may be a GitHub repository variable or secret. The other five values should be repository secrets. `JWT_SECRET` must contain at least 32 characters.

To enable `/profile`, also add the repository secrets `ADMIN_USERNAME` and `ADMIN_PASSWORD_HASH`. Supply both together; generate the hash with `npm run admin:password`. The workflow validates and uploads them without printing them. They are optional for existing app-only sync deployments.

At Worker runtime, Cloudflare receives only the secrets needed by the service:

```text
TURSO_DATABASE_URL
TURSO_AUTH_TOKEN
JWT_SECRET
```

The Worker also receives `ADMIN_USERNAME` and `ADMIN_PASSWORD_HASH` when those administrator secrets are supplied. An administrator password is never stored in plaintext.

## Local development

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

Deploy manually:

```bash
wrangler secret put TURSO_DATABASE_URL
wrangler secret put TURSO_AUTH_TOKEN
wrangler secret put JWT_SECRET
npx wrangler deploy --config wrangler.self-hosted.toml --name my-koinly-sync
```

`schema.sql` can be applied again without deleting existing sync data. `scripts/apply-schema.mjs` also migrates older `users.email` schemas to `users.username` and adds the recovery-key column.

## Administration portal

**Existing self-hosted Worker owners MUST redeploy after updating to receive `/profile` and account management.** Apply the latest schema first (the GitHub workflow does this automatically). The migration adds `users.session_version` and `admin_sessions` while preserving existing users and cloud data. App updates alone do not update a deployed Worker.

Visit `https://<worker-name>.<account-subdomain>.workers.dev/profile`. For example: `https://koinly-test.sweets-4c4.workers.dev/profile`.

The portal uses a dedicated administrator identity, not a regular sync account. Setup:

1. Run `npm run admin:password` in an interactive terminal. Choose and confirm a unique 12–256 character password. Input is hidden and only the salted hash is printed.
2. Choose a lowercase `ADMIN_USERNAME` (3–32 characters, letters/numbers/dots/dashes/underscores, starting and ending with a letter or number).
3. Add both repository secrets and redeploy using the GitHub workflow, or upload them manually to the **same Worker name**:

   ```bash
   npx wrangler secret put ADMIN_USERNAME --config wrangler.self-hosted.toml --name my-koinly-sync
   npx wrangler secret put ADMIN_PASSWORD_HASH --config wrangler.self-hosted.toml --name my-koinly-sync
   npx wrangler deploy --config wrangler.self-hosted.toml --name my-koinly-sync
   ```

4. Sign in at `/profile` using the configured username and original password, not its hash. For local development only, put the username and generated hash alongside your other development secrets in the ignored `.dev.vars` file and run `npm run dev`; use `http://localhost:8787/profile`. Use HTTPS for deployed Workers.

Account lists expose only IDs, usernames, creation/update timestamps, and status, with an exact total and 50 accounts per page. **Invited** means no device has signed in; **Active** means at least one has signed in historically, not that a session is online. The administrator is separate and excluded from this count.

Creation and reset accept 8–256 character account passwords. Share new passwords privately. New account holders can create a recovery key in Koinly after login. A reset immediately invalidates old access/refresh sessions and the recovery key. Confirmed deletion atomically removes the account, sync records, devices, sessions, and Telegram backup settings; existing local copies and previously sent Telegram files remain.

Security details:

- Administrator authentication is required on the server for every account-management endpoint. An app bearer token cannot authorize portal access.
- Random one-hour sessions use `__Host-koinly-admin` cookies with `Secure`, `HttpOnly`, `SameSite=Strict`, and `Path=/`. Turso stores only keyed session hashes. Sign-out revokes the session; changing either administrator secret or `JWT_SECRET` invalidates portal sessions.
- Write requests require an exact matching `Origin` and `X-Profile-Request: 1`. No portal route enables cross-origin requests. HTML/API responses are private and not cached; pages use a nonce-based CSP, frame protection, and no external assets.
- Login is limited to eight attempts per Cloudflare-provided client IP and fifty globally per fifteen minutes, using atomic counters in Turso. Database errors fail closed and return a safe message.
- New passwords use random 16-byte salts and PBKDF2-HMAC-SHA256 (100,000 iterations). This uses the existing verifier's format and [Cloudflare's native Web Crypto](https://developers.cloudflare.com/workers/runtime-apis/web-crypto/), subject to the runtime's [PBKDF2 iteration limit](https://github.com/cloudflare/workerd/issues/1346). Legacy salted hashes remain usable; changing/resetting a password writes the new format. No password/hash is sent back in account API responses, embedded in HTML, or saved in browser storage.
- Existing access tokens remain compatible until their account's session version changes. Every authenticated app request checks that version and account existence. Resets increment it and revoke refresh tokens; deletion removes the account.

To recover administrator access, regenerate `ADMIN_PASSWORD_HASH`, replace the saved deployment secret, and redeploy. Do not change `JWT_SECRET` for a routine administrator password reset, because it also protects existing Worker credentials and encrypted data. Missing administrator settings show a setup message and block the portal without disabling ordinary app sync.

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

Clients write SQLite first and queue entity operations. The Worker stores the current entity state, deduplicates operation IDs, appends ordered changes for other devices, and enforces authenticated user scoping.

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

Run:

```bash
npm run schema:apply
```

Then redeploy or recheck `/health`.

### Registration is closed

This is expected after the first owner account exists. Use **Login** from additional devices. If an older deployment used email login, redeploy the latest Worker first; the schema migration converts the old email local-part into the username.


### Password recovery

New registrations return a recovery key once. The Worker stores only a keyed hash of that recovery key. `POST /v1/auth/recover` accepts the username, recovery key, and new password, rate-limits failed attempts, revokes existing refresh tokens after a successful reset, and issues a new session.

An authenticated user can call `POST /v1/auth/recovery-key` to rotate the recovery key. Only the newly generated key remains valid.
