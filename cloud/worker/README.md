# Koinly Sync Worker

Cloudflare Worker backend for Koinly multi-device sync. The app talks to the
Worker, while Turso credentials remain in encrypted Worker secrets and never
ship inside the app.

## Deployment workflows

The repository keeps user and owner deployments separate:

- **Deploy User Self-Hosted Sync Worker** is the fork-friendly workflow. It
  runs manually or when Worker files change on `main`/`master`.
- **Deploy Owner Default Sync Worker** is manual-only and deploys the managed
  default service with invite-key registration and Telegram key delivery.

Both workflows reuse this Worker implementation while deploying independent
Cloudflare Workers and Turso databases.

## User self-hosted configuration

The user workflow requires these repository values:

```text
CLOUDFLARE_NAME_U
CLOUDFLARE_API_TOKEN_U
CLOUDFLARE_ACCOUNT_ID_U
TURSO_DATABASE_URL_U
TURSO_AUTH_TOKEN_U
JWT_SECRET_U
```

`JWT_SECRET_U` must contain at least 32 characters. Self-hosted deployments do
not require `REGISTRATION_ADMIN_SECRET`, `REGISTRATION_KEY_CHAT_ID`, or
`TELEGRAM_BOT_TOKEN`; those are reserved for the managed default service.

The workflow applies `schema.sql`, uploads the Turso and JWT values as
Cloudflare Worker secrets, deploys using `CLOUDFLARE_NAME_U`, and verifies the
deployed `/health` endpoint in `first-user` registration mode.

## Owner/default-service configuration

The owner workflow keeps the existing unprefixed GitHub values:

```text
CLOUDFLARE_NAME
CLOUDFLARE_API_TOKEN
CLOUDFLARE_ACCOUNT_ID
TURSO_DATABASE_URL
TURSO_AUTH_TOKEN
JWT_SECRET
TELEGRAM_BOT_TOKEN
REGISTRATION_KEY_CHAT_ID
REGISTRATION_ADMIN_SECRET
```

`JWT_SECRET` and `REGISTRATION_ADMIN_SECRET` must each contain at
least 32 characters and must be different. The workflow validates the values,
deploys in `invite-key` mode, creates an active registration key, and confirms
Telegram delivery. Fork users do not need these owner values.

Only user self-hosted GitHub configuration uses the `_U` suffix. The user
workflow maps those values to the standard Worker runtime names; the owner
workflow uses the unprefixed names directly.

## User self-hosted registration

A new self-hosted backend accepts one owner account without a registration
key. Registration closes after that account is created. Additional devices
must log in with the same owner account. This keeps a public `workers.dev`
endpoint from allowing unlimited account creation without adding a separate
invite system.

## Local deployment

Install dependencies, apply the schema, and add runtime secrets:

```bash
npm ci
npm run typecheck
npm test
npm run schema:apply
wrangler secret put TURSO_DATABASE_URL
wrangler secret put TURSO_AUTH_TOKEN
wrangler secret put JWT_SECRET
npx wrangler deploy --name my-koinly-sync
```

`schema.sql` is idempotent, so applying it again does not erase existing sync
data.

The Cloudflare API token used by automation should be scoped to the target
account and created from the **Edit Cloudflare Workers** template. A standard
`workers.dev` deployment needs Workers Scripts edit access plus account and
membership read access. Custom routes or domains may need Workers Routes edit
access too.

## Health check

Open `https://<worker-name>.<account-subdomain>.workers.dev/health`. A ready
self-hosted backend returns values equivalent to:

```json
{
  "ok": true,
  "service": "koinly-sync",
  "configured": true,
  "registrationMode": "first-user",
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

## Sync model

Clients write local SQLite first and queue entity operations. The Worker
deduplicates operations by ID, stores each user's current entity state, and
appends ordered changes for other devices to pull. Backup restore uses
`POST /v1/sync/replace` to replace only the authenticated user's cloud state.

The backend uses tenant-scoped queries, password hashing, signed short-lived
access tokens, rotating refresh tokens, bounded batches, idempotent operation
IDs, stale-version conflict checks, and transactional database writes.

## Troubleshooting

If deployment health returns Cloudflare error `1042`, confirm
`TURSO_DATABASE_URL` is the `libsql://*.turso.io` value printed by the Turso
CLI. A Worker URL or same-account Worker proxy can create a request loop that
Cloudflare blocks before the health endpoint can return JSON. The deployment
workflow uses Wrangler's exact reported target and prints the HTTP response to
make this failure clear.
