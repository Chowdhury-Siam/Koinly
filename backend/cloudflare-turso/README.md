# Koinly Cloudflare + Turso Sync Backend

This backend gives the Flutter app a free/low-cost online sync target:

- Cloudflare Worker: HTTP API + small admin panel.
- Turso: SQLite-compatible cloud database for sync snapshots.
- App model: local SQLite remains the source of truth; the app uploads/downloads one snapshot per Sync ID.
- Admin approval: new Sync IDs are created as pending and must be approved before cloud sync is allowed.

## 1. Create Turso database

```bash
turso db create koinly-sync
turso db show koinly-sync --url
turso db tokens create koinly-sync
```

Save the database URL and auth token for the Cloudflare Worker secrets.

The Worker now creates the `sync_snapshots` and `sync_users` tables automatically on the first API/admin request. Running `schema.sql` manually is optional.

## 2. Deploy the Cloudflare Worker from Cloudflare website

Use these build settings:

| Field | Value |
|---|---|
| Path | `backend/cloudflare-turso` |
| Build command | `npm install` |
| Deploy command | `npx wrangler deploy --config wrangler.toml` |
| Non-production deploy command | `npx wrangler deploy --config wrangler.toml` |

This repo includes the real `wrangler.toml`, so Cloudflare should deploy it as a Worker instead of trying to detect a static website.

Add these Worker secrets in Cloudflare Dashboard:

```text
TURSO_DATABASE_URL
TURSO_AUTH_TOKEN
SYNC_SECRET
ADMIN_KEY
```

Use a long random value for `SYNC_SECRET` and `ADMIN_KEY`.

## 3. Build the Flutter app with your Worker URL

The app no longer shows a **Cloudflare Worker URL** input field. Put the Worker URL into the APK at build time instead:

```bash
flutter build apk --release \
  --no-tree-shake-icons \
  --dart-define=KOINLY_SYNC_API_BASE_URL=https://koinly-sync.yourname.workers.dev
```

For GitHub Actions, add this repository variable or secret:

```text
KOINLY_SYNC_API_BASE_URL=https://koinly-sync.yourname.workers.dev
```

The included GitHub Actions workflow also has a manual `sync_api_base_url` input.

## 4. Admin panel

Open:

```text
https://koinly-sync.yourname.workers.dev/admin
```

Enter the `ADMIN_KEY` secret to login. The panel shows Sync ID, approval status, payload size, device, and update time. It deliberately does not display the finance payload. Use **Approve**, **Reject**, or **Block** to control who can sync data. Existing Sync IDs that already have snapshots are automatically migrated as approved, so old users do not need approval again.

## Notes

- Conflict handling is last-upload-wins. For one user with two devices, manually download before editing on a second device.
- This starter sync stores a full JSON backup snapshot. It is simple and reliable for a personal finance app, but not a full realtime multi-user sync engine.
- Use HTTPS only. Never expose `TURSO_AUTH_TOKEN`, `SYNC_SECRET`, or `ADMIN_KEY` in the Flutter app.
