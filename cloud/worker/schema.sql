CREATE TABLE IF NOT EXISTS users (
  id TEXT PRIMARY KEY,
  username TEXT NOT NULL UNIQUE,
  password_hash TEXT NOT NULL,
  recovery_key_hash TEXT,
  session_version INTEGER NOT NULL DEFAULT 0,
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

CREATE TABLE IF NOT EXISTS admin_sessions (
  token_hash TEXT PRIMARY KEY,
  expires_at INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_refresh_tokens_user ON refresh_tokens(user_id, device_id);
CREATE INDEX IF NOT EXISTS idx_devices_user ON devices(user_id, last_seen_at DESC);
CREATE INDEX IF NOT EXISTS idx_sync_changes_user_sequence ON sync_changes(user_id, sequence);
CREATE INDEX IF NOT EXISTS idx_sync_entities_user_updated ON sync_entities(user_id, updated_at DESC);

CREATE TABLE IF NOT EXISTS telegram_backup_settings (
  user_id TEXT PRIMARY KEY,
  enabled INTEGER NOT NULL DEFAULT 0 CHECK(enabled IN (0, 1)),
  bot_token_encrypted TEXT,
  bot_token_iv TEXT,
  chat_id TEXT NOT NULL DEFAULT '',
  frequency TEXT NOT NULL DEFAULT 'daily' CHECK(frequency IN ('daily', 'weekly', 'monthly')),
  hour INTEGER NOT NULL DEFAULT 2 CHECK(hour BETWEEN 0 AND 23),
  minute INTEGER NOT NULL DEFAULT 0 CHECK(minute BETWEEN 0 AND 59),
  weekday INTEGER NOT NULL DEFAULT 7 CHECK(weekday BETWEEN 1 AND 7),
  month_day INTEGER NOT NULL DEFAULT 1 CHECK(month_day BETWEEN 1 AND 31),
  timezone_offset_minutes INTEGER NOT NULL DEFAULT 0 CHECK(timezone_offset_minutes BETWEEN -840 AND 840),
  next_due_at INTEGER,
  last_sent_at INTEGER,
  last_attempt_at INTEGER,
  last_error TEXT,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY(user_id) REFERENCES users(id)
);

CREATE INDEX IF NOT EXISTS idx_telegram_backup_due
  ON telegram_backup_settings(enabled, next_due_at);

CREATE TABLE IF NOT EXISTS analytics_upload_settings (
  user_id TEXT PRIMARY KEY,
  google_client_id TEXT NOT NULL DEFAULT '',
  google_client_secret_encrypted TEXT,
  google_client_secret_iv TEXT,
  google_refresh_token_encrypted TEXT,
  google_refresh_token_iv TEXT,
  google_account_email TEXT NOT NULL DEFAULT '',
  google_connected_at INTEGER,
  google_last_upload_at INTEGER,
  google_last_error TEXT,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY(user_id) REFERENCES users(id)
);

-- Profile media is stored separately from finance sync rows so large photos,
-- GIFs, and short videos never inflate the realtime sync change log. Uploads
-- are chunked and the active metadata row is switched only after all chunks
-- have arrived successfully.
CREATE TABLE IF NOT EXISTS profile_media (
  user_id TEXT PRIMARY KEY,
  version TEXT NOT NULL,
  original_name TEXT NOT NULL,
  media_kind TEXT NOT NULL CHECK(media_kind IN ('photo', 'gif', 'video')),
  size_bytes INTEGER NOT NULL CHECK(size_bytes > 0 AND size_bytes <= 52428800),
  chunk_count INTEGER NOT NULL CHECK(chunk_count > 0 AND chunk_count <= 128),
  scale REAL NOT NULL DEFAULT 1.0,
  alignment_x REAL NOT NULL DEFAULT 0.0,
  alignment_y REAL NOT NULL DEFAULT 0.0,
  updated_at INTEGER NOT NULL,
  FOREIGN KEY(user_id) REFERENCES users(id)
);

CREATE TABLE IF NOT EXISTS profile_media_chunks (
  user_id TEXT NOT NULL,
  version TEXT NOT NULL,
  chunk_index INTEGER NOT NULL CHECK(chunk_index >= 0 AND chunk_index < 128),
  data_base64 TEXT NOT NULL,
  PRIMARY KEY(user_id, version, chunk_index),
  FOREIGN KEY(user_id) REFERENCES users(id)
);

CREATE INDEX IF NOT EXISTS idx_profile_media_chunks_user_version
  ON profile_media_chunks(user_id, version, chunk_index);
