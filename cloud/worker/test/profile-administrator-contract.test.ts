import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const worker = readFileSync(new URL('../src/index.ts', import.meta.url), 'utf8');
const profile = readFileSync(new URL('../src/profile.ts', import.meta.url), 'utf8');

test('profile portal uses the first database account as administrator', () => {
  assert.match(worker, /administratorAccount\(db\)/);
  assert.match(worker, /deploymentRecoveryOwnerUserId\(db\)/);
  assert.match(worker, /SELECT id FROM users ORDER BY created_at ASC, id ASC LIMIT 1/);
  assert.match(worker, /administratorUserId/);
  assert.match(worker, /first Koinly account in the app/);
  assert.match(worker, /administrator account cannot be deleted/);
  assert.doesNotMatch(worker, /ADMIN_USERNAME|ADMIN_PASSWORD_HASH/);
});

test('profile portal supports username changes while preserving account identity', () => {
  assert.match(worker, /match\[2\] === '\/username'/);
  assert.match(worker, /UPDATE users SET username = \?, updated_at = \? WHERE id = \?/);
  assert.match(profile, /id="username-dialog"/);
  assert.match(profile, /data-action="username">Change username/);
  assert.match(profile, /account-role/);
  assert.match(profile, />Administrator<\/span>/);
});

test('profile portal matches the current Koinly app palette', () => {
  for (const color of ['#0F1216', '#13181D', '#14191E', '#192126', '#272F35', '#ADB5BB', '#00BD91', '#27C6A0', '#FF5353', '#F6F9F6', '#FFFFFF', '#F3F8F4', '#ECF4EF', '#D9E7DE']) {
    assert.ok(profile.includes(color), `missing ${color}`);
  }
});
