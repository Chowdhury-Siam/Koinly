import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';

const worker = fs.readFileSync(new URL('../src/index.ts', import.meta.url), 'utf8');
const schema = fs.readFileSync(new URL('../schema.sql', import.meta.url), 'utf8');
const migration = fs.readFileSync(new URL('../scripts/apply-schema.mjs', import.meta.url), 'utf8');

test('authentication is username based and exposes recovery endpoints', () => {
  assert.match(schema, /username TEXT NOT NULL UNIQUE/);
  assert.match(schema, /recovery_key_hash TEXT/);
  assert.doesNotMatch(schema, /email TEXT NOT NULL UNIQUE/);

  assert.match(worker, /body\.username/);
  assert.match(worker, /POST \/v1\/auth\/recover/);
  assert.match(worker, /POST \/v1\/auth\/recovery-key/);
  assert.match(worker, /Invalid username or password/);
  assert.doesNotMatch(worker, /body\.email/);
});

test('password recovery is rate limited and revokes existing refresh sessions', () => {
  assert.match(worker, /enforceRateLimit\(db, `recover:\$\{username\}`/);
  assert.match(worker, /UPDATE refresh_tokens SET revoked_at = \? WHERE user_id = \? AND revoked_at IS NULL/);
  assert.match(worker, /hashRecoveryKey\(recoveryKey, env\.JWT_SECRET\)/);
  assert.match(worker, /cache-control', 'no-store, private/);
});

test('legacy email schemas migrate without deleting the owner account', () => {
  assert.match(migration, /ALTER TABLE users RENAME COLUMN email TO username/);
  assert.match(migration, /ALTER TABLE users ADD COLUMN recovery_key_hash TEXT/);
  assert.match(migration, /legacyUsername/);
});
