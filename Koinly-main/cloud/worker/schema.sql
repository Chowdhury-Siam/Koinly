CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY,
  email TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS refresh_tokens (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  token_hash TEXT NOT NULL UNIQUE,
  device_id TEXT NOT NULL,
  expires_at INTEGER NOT NULL,
  revoked_at INTEGER,
  created_at INTEGER NOT NULL,
  rotated_at INTEGER,
  FOREIGN KEY(user_id) REFERENCES users(id)
);

CREATE TABLE IF NOT EXISTS devices (
  id TEXT NOT NULL,
  user_id TEXT NOT NULL,
  name TEXT NOT NULL,
  platform TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  last_seen_at INTEGER NOT NULL,
  revoked_at INTEGER,
  PRIMARY KEY(user_id, id),
  FOREIGN KEY(user_id) REFERENCES users(id)
);

CREATE TABLE IF NOT EXISTS sync_entities (
  user_id TEXT NOT NULL,
  entity_type TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  version INTEGER NOT NULL,
  payload_json TEXT NOT NULL,
  deleted_at INTEGER,
  updated_at INTEGER NOT NULL,
  last_operation_id TEXT NOT NULL,
  PRIMARY KEY(user_id, entity_type, entity_id),
  FOREIGN KEY(user_id) REFERENCES users(id)
);

CREATE TABLE IF NOT EXISTS sync_changes (
  sequence INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id TEXT NOT NULL,
  entity_type TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  operation TEXT NOT NULL,
  version INTEGER NOT NULL,
  payload_json TEXT,
  device_id TEXT NOT NULL,
  operation_id TEXT NOT NULL,
  changed_at INTEGER NOT NULL,
  FOREIGN KEY(user_id) REFERENCES users(id)
);

CREATE TABLE IF NOT EXISTS processed_operations (
  user_id TEXT NOT NULL,
  operation_id TEXT NOT NULL,
  sequence INTEGER NOT NULL,
  created_at INTEGER NOT NULL,
  PRIMARY KEY(user_id, operation_id),
  FOREIGN KEY(user_id) REFERENCES users(id)
);

CREATE TABLE IF NOT EXISTS rate_limits (
  key TEXT PRIMARY KEY,
  window_start INTEGER NOT NULL,
  count INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS registration_keys (
  id TEXT PRIMARY KEY,
  key_hash TEXT NOT NULL UNIQUE,
  encrypted_key TEXT NOT NULL,
  encryption_iv TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  expires_at INTEGER,
  used_at INTEGER,
  used_by_user_id TEXT,
  status TEXT NOT NULL CHECK(status IN ('ACTIVE', 'USED', 'REVOKED', 'EXPIRED')),
  revoked_at INTEGER,
  created_by TEXT NOT NULL,
  delivery_status TEXT NOT NULL DEFAULT 'PENDING' CHECK(delivery_status IN ('PENDING', 'DELIVERED', 'FAILED')),
  delivery_attempts INTEGER NOT NULL DEFAULT 0,
  last_delivery_attempt_at INTEGER,
  delivered_at INTEGER,
  delivery_error TEXT,
  FOREIGN KEY(used_by_user_id) REFERENCES users(id)
);

CREATE INDEX IF NOT EXISTS idx_refresh_tokens_user ON refresh_tokens(user_id, device_id);
CREATE INDEX IF NOT EXISTS idx_devices_user ON devices(user_id, last_seen_at DESC);
CREATE INDEX IF NOT EXISTS idx_sync_changes_user_sequence ON sync_changes(user_id, sequence);
CREATE INDEX IF NOT EXISTS idx_sync_entities_user_updated ON sync_entities(user_id, updated_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS idx_registration_keys_one_active ON registration_keys(status) WHERE status = 'ACTIVE';
CREATE INDEX IF NOT EXISTS idx_registration_keys_created ON registration_keys(created_at DESC);
