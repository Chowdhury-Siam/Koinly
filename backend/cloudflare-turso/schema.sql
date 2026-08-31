CREATE TABLE IF NOT EXISTS sync_snapshots (
  sync_id TEXT PRIMARY KEY,
  pin_hash TEXT NOT NULL,
  payload_json TEXT NOT NULL,
  payload_bytes INTEGER NOT NULL DEFAULT 0,
  device_id TEXT NOT NULL DEFAULT '',
  client_updated_at TEXT NOT NULL DEFAULT '',
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
);

CREATE INDEX IF NOT EXISTS idx_sync_snapshots_updated_at
  ON sync_snapshots(updated_at DESC);

CREATE TABLE IF NOT EXISTS sync_users (
  sync_id TEXT PRIMARY KEY,
  pin_hash TEXT NOT NULL DEFAULT '',
  status TEXT NOT NULL DEFAULT 'pending',
  device_id TEXT NOT NULL DEFAULT '',
  first_seen_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  last_seen_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
  decided_at TEXT NOT NULL DEFAULT '',
  note TEXT NOT NULL DEFAULT ''
);

CREATE INDEX IF NOT EXISTS idx_sync_users_status_seen
  ON sync_users(status, last_seen_at DESC);

INSERT OR IGNORE INTO sync_users(sync_id, pin_hash, status, device_id, first_seen_at, last_seen_at, decided_at, note)
SELECT sync_id, pin_hash, 'approved', device_id, created_at, updated_at, updated_at, 'Migrated from existing sync snapshot.'
FROM sync_snapshots;
