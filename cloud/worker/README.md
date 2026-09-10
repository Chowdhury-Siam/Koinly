# Koinly Self-Hosted Sync Worker

Cloudflare Worker backend for Koinly multi-device synchronization. Finance data
is stored in the user's Turso database. Turso credentials and `JWT_SECRET` stay
in Cloudflare Worker secrets and are never shipped inside the Flutter app.

## Registration model

A fresh Worker accepts exactly one owner account. After the first account is
created, registration closes. Additional devices sign in with the same account.

The public health response reports:

```json
{
  "service": "koinly-sync",
  "registrationMode": "first-user"
}
```

## Required Worker secrets

```text
TURSO_DATABASE_URL
TURSO_AUTH_TOKEN
JWT_SECRET
```

`JWT_SECRET` must contain at least 32 characters.

The GitHub deployment workflow reads these repository values and maps them to
the Worker runtime names:

```text
CLOUDFLARE_NAME_U
CLOUDFLARE_API_TOKEN_U
CLOUDFLARE_ACCOUNT_ID_U
TURSO_DATABASE_URL_U
TURSO_AUTH_TOKEN_U
JWT_SECRET_U
```

## Local deployment

```bash
npm ci
npm run typecheck
npm test
npm run schema:apply
wrangler secret put TURSO_DATABASE_URL
wrangler secret put TURSO_AUTH_TOKEN
wrangler secret put JWT_SECRET
npx wrangler deploy --config wrangler.self-hosted.toml --name my-koinly-sync
```

`schema.sql` is idempotent and can be applied again without deleting existing
sync data.

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

Clients write SQLite first and queue entity operations. The Worker deduplicates
operation IDs, stores current entity state, appends ordered changes for other
devices, and enforces authenticated user scoping.

The Flutter client uses merge-first synchronization. Full local reconciliation
can enqueue the complete device snapshot, while full cloud restore merges the
remote state into the device instead of deleting local-only data.

`MAX_SYNC_BATCH_SIZE` defaults to `100`. `MAX_SYNC_REPLACE_SIZE` defaults to
`25000` for large reconciliation payloads.

## Telegram `.koinlybackup`

`wrangler.self-hosted.toml` configures a Cron Trigger every five minutes. Users
configure the optional Telegram bot from the authenticated Koinly app.

The Worker:

- validates the bot and target chat;
- encrypts the bot token with AES-GCM using key material derived from
  `JWT_SECRET`;
- stores only the encrypted token and IV in Turso;
- builds a portable `.koinlybackup` from synchronized cloud entities;
- falls back to reconstructing active data from sync history when needed;
- refuses to send an empty finance backup; and
- supports daily, weekly, and monthly schedules plus manual upload.

For Telegram channels, the bot must be an administrator with permission to post
messages.

## Troubleshooting

### Cloudflare error 1042

`TURSO_DATABASE_URL` must be a Turso `libsql://*.turso.io` URL. Do not point it
at another Worker. Remove Worker proxy routes that loop back into the same
account deployment.

### Schema is not ready

Run:

```bash
npm run schema:apply
```

Then redeploy or recheck `/health`.

### Registration is closed

This is expected after the first owner account exists. Use Login from additional
devices.
