# Koinly Self-Hosted Sync Worker

This is the optional backend used when a Koinly user wants multi-device synchronization.
The Worker runs on Cloudflare and stores synchronized finance data in the user's Turso database.

For the easiest setup, follow the beginner-friendly guide in the repository's main [`README.md`](../../README.md).

## Registration model

A fresh Worker accepts one owner account identified by a username. Email addresses are not used for authentication. Registration returns a one-time recovery key; after registration closes, additional devices use **Login** with the same username and password.

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

At Worker runtime, Cloudflare receives only the secrets needed by the service:

```text
TURSO_DATABASE_URL
TURSO_AUTH_TOKEN
JWT_SECRET
```

## Local development

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
