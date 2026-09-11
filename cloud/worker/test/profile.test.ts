import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { createHash, createHmac } from 'node:crypto';
import test from 'node:test';
import { createClient } from '@libsql/client';
import worker, { profile, hashPassword, verifyPassword, requireAuth, login, refresh, register, recoverAccount, rotateRecoveryKey } from '../src/index.ts';
import { deploymentSecrets } from '../scripts/prepare-secrets.mjs';

const origin = 'https://worker.example';
const schema = fs.readFileSync(new URL('../schema.sql', import.meta.url), 'utf8');
const adminPassword = 'administrator-test-password';

test('profile authentication and account lifecycle use the real database', async t => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'koinly-profile-'));
  const databaseUrl = 'file:' + path.join(directory, 'test.db').replaceAll('\\', '/');
  const connect = () => createClient({ url: databaseUrl });
  const db = connect();
  t.after(async () => { db.close(); await fs.promises.rm(directory, { recursive: true, force: true, maxRetries: 5, retryDelay: 100 }); });
  await db.executeMultiple(schema);
  const env = await deploymentSecrets({ TURSO_DATABASE_URL: databaseUrl, TURSO_AUTH_TOKEN: 'local-test', JWT_SECRET: 'x'.repeat(40), ADMIN_USERNAME: 'worker-admin', ADMIN_PASSWORD: adminPassword });
  let cookie = '';
  const request = (route: string, method = 'GET', body?: unknown, headers: Record<string, string> = {}) => new Request(origin + route, {
    method, headers: { origin, 'x-profile-request': '1', 'content-type': 'application/json', cookie, ...headers },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const call = (route: string, method = 'GET', body?: unknown, headers: Record<string, string> = {}) => profile(request(route, method, body, headers), env, connect);

  await t.test('login page is public; account markup, data, and mutations are protected', async () => {
    const page = await call('/profile');
    const html = await page.text();
    assert.match(html, /id="login-form"/);
    assert.doesNotMatch(html, /id="dashboard"|id="accounts"/);
    assert.match(page.headers.get('cache-control')!, /no-store/);
    assert.match(page.headers.get('content-security-policy')!, /frame-ancestors 'none'/);
    assert.equal(page.headers.get('access-control-allow-origin'), null);
    for (const [route, method, body] of [
      ['/profile/api/accounts', 'GET'], ['/profile/api/accounts', 'POST', { username: 'intruder', password: 'secret123' }],
      ['/profile/api/accounts/any-id/password', 'POST', { password: 'secret123' }], ['/profile/api/accounts/any-id', 'DELETE'],
    ] as const) {
      assert.equal((await call(route, method, body)).status, 401);
    }
    const closed = await worker.fetch(request('/profile/api/accounts'), { ...env, ADMIN_PASSWORD_HASH: undefined }, {} as never);
    assert.equal(closed.status, 503);
    assert.equal(closed.headers.get('access-control-allow-origin'), null);
    assert.equal((await profile(request('/profile/api/accounts'), { ...env, ADMIN_PASSWORD_HASH: 'plaintext-is-not-accepted' }, connect)).status, 503);
  });

  await t.test('login enforces origin, body validation, credentials, and secure cookies', async () => {
    const credentials = { username: env.ADMIN_USERNAME, password: adminPassword };
    assert.equal((await call('/profile/api/login', 'POST', credentials, { origin: 'https://evil.example' })).status, 403);
    assert.equal((await call('/profile/api/login', 'POST', credentials, { 'x-profile-request': '' })).status, 403);
    assert.equal((await call('/profile/api/login', 'OPTIONS')).status, 405);
    assert.equal((await call('/profile/api/login', 'POST', null)).status, 400);
    assert.equal((await call('/profile/api/login', 'POST', { ...credentials, password: 'wrong' })).status, 401);
    const response = await call('/profile/api/login', 'POST', credentials);
    assert.equal(response.status, 200);
    const setCookie = response.headers.get('set-cookie')!;
    assert.match(setCookie, /^__Host-koinly-admin=/);
    for (const flag of ['HttpOnly', 'Secure', 'SameSite=Strict', 'Path=/', 'Max-Age=3600']) assert.ok(setCookie.includes(flag));
    cookie = setCookie.split(';')[0];
    const stored = (await db.execute('SELECT token_hash FROM admin_sessions')).rows;
    assert.equal(stored.length, 1);
    assert.notEqual(stored[0].token_hash, cookie.split('=')[1]);
    assert.match(await (await call('/profile')).text(), /id="dashboard"/);
  });

  let accountId: string;
  await t.test('create validates inputs and handles case-insensitive duplicates without exposing hashes', async () => {
    for (const username of ['a', 'ab', '_bad', 'bad_', '<script>', 'x'.repeat(33)]) {
      assert.equal((await call('/profile/api/accounts', 'POST', { username, password: 'password123' })).status, 400);
    }
    for (const password of ['short', 'x'.repeat(257), {}, null]) {
      assert.equal((await call('/profile/api/accounts', 'POST', { username: 'alice', password })).status, 400);
    }
    assert.equal((await call('/profile/api/accounts', 'POST', { username: 'Alice', password: 'password123' })).status, 201);
    const duplicate = await call('/profile/api/accounts', 'POST', { username: 'ALICE', password: 'password123' });
    assert.equal(duplicate.status, 409);
    assert.match(await duplicate.text(), /Duplicate username/);
    const data = await (await call('/profile/api/accounts')).json();
    assert.equal(data.total, 1);
    assert.equal(data.accounts[0].username, 'alice');
    assert.equal(data.accounts[0].status, 'invited');
    assert.ok(data.accounts[0].createdAt > 0);
    assert.doesNotMatch(JSON.stringify(data), /password|recovery|token/);
    accountId = data.accounts[0].id;
    const row = (await db.execute('SELECT password_hash FROM users')).rows[0];
    assert.match(String(row.password_hash), /^pbkdf2\$100000\$/);
    assert.equal(await verifyPassword('password123', String(row.password_hash)), true);
    assert.equal(await verifyPassword('incorrect', String(row.password_hash)), false);
    assert.notEqual(await hashPassword('password123'), row.password_hash);
    assert.equal((await call('/profile/api/accounts', 'POST', { username: 'large', password: 'x'.repeat(9000) })).status, 413);
    assert.equal((await call('/profile/api/accounts', 'POST', {}, { 'content-type': 'text/plain' })).status, 415);
    assert.equal((await call('/profile/api/accounts?page=NaN')).status, 400);
  });

  let oldAccess: string;
  await t.test('reset invalidates access, refresh, and recovery credentials; new password works', async () => {
    const session = await (await login(request('/v1/auth/login', 'POST', { username: 'alice', password: 'password123', deviceId: 'test-device' }), env, db)).json();
    oldAccess = session.accessToken;
    const oldAuth = await requireAuth(request('/v1/sync/status', 'GET', undefined, { authorization: 'Bearer ' + oldAccess }), env, db);
    const listed = await (await call('/profile/api/accounts')).json();
    assert.equal(listed.accounts[0].status, 'active');
    assert.equal((await call('/profile/api/accounts', 'GET', undefined, { cookie: '', authorization: 'Bearer ' + oldAccess })).status, 401);
    assert.equal((await call('/profile/api/accounts', 'GET', undefined, { cookie: '__Host-koinly-admin=' + oldAccess })).status, 401);
    await db.execute({ sql: 'UPDATE users SET recovery_key_hash = ? WHERE id = ?', args: ['old-recovery-hash', accountId] });
    assert.equal((await call('/profile/api/accounts/' + accountId + '/password', 'POST', { password: 'new-password123' }, { origin: 'https://evil.example' })).status, 403);
    const result = await call('/profile/api/accounts/' + accountId + '/password', 'POST', { password: 'new-password123' });
    assert.equal(result.status, 200);
    assert.equal((await db.execute('SELECT recovery_key_hash FROM users')).rows[0].recovery_key_hash, null);
    await assert.rejects(requireAuth(request('/v1/sync/status', 'GET', undefined, { authorization: 'Bearer ' + oldAccess }), env, db), /revoked/);
    await assert.rejects(rotateRecoveryKey(env, db, oldAuth), /revoked/);
    await assert.rejects(refresh(request('/v1/auth/refresh', 'POST', { refreshToken: session.refreshToken, deviceId: 'test-device' }), env, db), /invalid or expired/);
    await assert.rejects(login(request('/v1/auth/login', 'POST', { username: 'alice', password: 'password123', deviceId: 'test-device' }), env, db), /Invalid username or password/);
    const next = await (await login(request('/v1/auth/login', 'POST', { username: 'alice', password: 'new-password123', deviceId: 'test-device' }), env, db)).json();
    await requireAuth(request('/v1/sync/status', 'GET', undefined, { authorization: 'Bearer ' + next.accessToken }), env, db);
    oldAccess = next.accessToken;
    assert.equal((await call('/profile/api/accounts/no-such-id/password', 'POST', { password: 'new-password123' })).status, 404);
  });

  await t.test('legacy hashes and access tokens survive deployment; recovery revokes them', async () => {
    const salt = 'legacy-salt';
    const legacyHash = 's256$' + salt + '$' + createHash('sha256').update(salt + '.' + env.JWT_SECRET + '.legacy-password').digest('base64url');
    await db.execute({ sql: 'INSERT INTO users(id, username, password_hash, created_at, updated_at) VALUES (?, ?, ?, 1, 1)', args: ['legacy-id', 'legacy-user', legacyHash] });
    const body = Buffer.from(JSON.stringify({ sub: 'legacy-id', username: 'legacy-user', deviceId: 'old-device', exp: Math.floor(Date.now() / 1000) + 900 })).toString('base64url');
    const header = Buffer.from(JSON.stringify({ alg: 'HS256', typ: 'JWT' })).toString('base64url');
    const token = header + '.' + body + '.' + createHmac('sha256', env.JWT_SECRET).update(header + '.' + body).digest('base64url');
    const auth = await requireAuth(request('/v1/sync/status', 'GET', undefined, { authorization: 'Bearer ' + token }), env, db);
    const session = await (await login(request('/v1/auth/login', 'POST', { username: 'legacy-user', password: 'legacy-password', deviceId: 'old-device' }), env, db)).json();
    const { recoveryKey } = await (await rotateRecoveryKey(env, db, auth)).json();
    const recovered = await (await recoverAccount(request('/v1/auth/recover', 'POST', { username: 'legacy-user', recoveryKey, newPassword: 'recovered-password', deviceId: 'new-device' }), env, db)).json();
    await requireAuth(request('/v1/sync/status', 'GET', undefined, { authorization: 'Bearer ' + recovered.accessToken }), env, db);
    await assert.rejects(requireAuth(request('/v1/sync/status', 'GET', undefined, { authorization: 'Bearer ' + token }), env, db), /revoked/);
    await assert.rejects(refresh(request('/v1/auth/refresh', 'POST', { refreshToken: session.refreshToken, deviceId: 'old-device' }), env, db), /invalid or expired/);
    await call('/profile/api/accounts/legacy-id', 'DELETE');
  });

  await t.test('pagination counts every account and does not repeat or omit rows', async () => {
    await db.batch(Array.from({ length: 52 }, (_, index) => ({ sql: 'INSERT INTO users(id, username, password_hash, created_at, updated_at) VALUES (?, ?, ?, 1, 1)', args: ['page-id-' + index, 'page-user-' + index, 'unused-test-hash'] })), 'write');
    const first = await (await call('/profile/api/accounts?page=1')).json();
    const second = await (await call('/profile/api/accounts?page=2')).json();
    assert.equal(first.total, 53); assert.equal(first.accounts.length, 50); assert.equal(second.accounts.length, 3);
    assert.equal(new Set([...first.accounts, ...second.accounts].map(account => account.id)).size, 53);
    await db.execute("DELETE FROM users WHERE id LIKE 'page-id-%'");
  });

  await t.test('delete is atomic, removes related data, preserves other accounts, and never reopens registration', async () => {
    await call('/profile/api/accounts', 'POST', { username: 'bob', password: 'password123' });
    const now = Date.now();
    await db.batch([
      { sql: 'INSERT INTO sync_entities VALUES (?, ?, ?, 1, ?, NULL, ?, ?)', args: [accountId, 'accounts', 'item', '{}', now, 'op'] },
      { sql: 'INSERT INTO sync_changes(user_id, entity_type, entity_id, operation, version, device_id, operation_id, changed_at) VALUES (?, ?, ?, ?, 1, ?, ?, ?)', args: [accountId, 'accounts', 'item', 'upsert', 'test-device', 'op', now] },
      { sql: 'INSERT INTO processed_operations VALUES (?, ?, 1, ?)', args: [accountId, 'op', now] },
      { sql: 'INSERT INTO telegram_backup_settings(user_id, updated_at) VALUES (?, ?)', args: [accountId, now] },
      `CREATE TRIGGER fail_delete BEFORE DELETE ON users BEGIN SELECT RAISE(ABORT, 'private database detail'); END`,
    ], 'write');
    const failed = await call('/profile/api/accounts/' + accountId, 'DELETE');
    assert.equal(failed.status, 503);
    assert.doesNotMatch(await failed.text(), /private database detail/);
    for (const table of ['sync_entities', 'sync_changes', 'processed_operations', 'telegram_backup_settings', 'refresh_tokens', 'devices']) {
      assert.ok(Number((await db.execute({ sql: `SELECT COUNT(*) AS count FROM ${table} WHERE user_id = ?`, args: [accountId] })).rows[0].count) > 0, table + ' should survive rollback');
    }
    await db.execute('DROP TRIGGER fail_delete');
    assert.equal((await call('/profile/api/accounts/' + accountId, 'DELETE')).status, 200);
    for (const table of ['sync_entities', 'sync_changes', 'processed_operations', 'telegram_backup_settings', 'refresh_tokens', 'devices']) {
      assert.equal(Number((await db.execute({ sql: `SELECT COUNT(*) AS count FROM ${table} WHERE user_id = ?`, args: [accountId] })).rows[0].count), 0);
    }
    await assert.rejects(requireAuth(request('/v1/sync/status', 'GET', undefined, { authorization: 'Bearer ' + oldAccess }), env, db), /revoked/);
    assert.equal((await call('/profile/api/accounts/' + accountId, 'DELETE')).status, 404);
    const accounts = await (await call('/profile/api/accounts')).json();
    assert.equal(accounts.total, 1); assert.equal(accounts.accounts[0].username, 'bob');
    await call('/profile/api/accounts/' + accounts.accounts[0].id, 'DELETE');
    await assert.rejects(register(request('/v1/auth/register', 'POST', { username: 'outsider', password: 'password123', deviceId: 'new-device' }), env, db), /administrator/);
    assert.equal((await (await call('/profile/api/accounts')).json()).total, 0);
  });

  await t.test('credential rotation, expiry, logout, tampering, and throttling are enforced', async () => {
    assert.equal((await profile(request('/profile/api/accounts'), { ...env, ADMIN_USERNAME: 'other-admin' }, connect)).status, 401);
    assert.equal((await profile(request('/profile/api/accounts'), { ...env, JWT_SECRET: 'y'.repeat(40) }, connect)).status, 401);
    assert.equal((await profile(request('/profile/api/accounts'), { ...env, ADMIN_PASSWORD_HASH: await hashPassword(adminPassword) }, connect)).status, 401);
    assert.equal((await call('/profile/api/accounts', 'GET', undefined, { cookie: cookie + 'tamper' })).status, 401);
    assert.equal((await call('/profile/api/logout', 'POST', {}, { origin: 'https://evil.example' })).status, 403);
    const oldCookie = cookie;
    const signedOut = await call('/profile/api/logout', 'POST', {});
    assert.match(signedOut.headers.get('set-cookie')!, /Max-Age=0/);
    assert.equal((await call('/profile/api/accounts', 'GET', undefined, { cookie: oldCookie })).status, 401);
    await db.execute('DELETE FROM rate_limits');
    const signedIn = await call('/profile/api/login', 'POST', { username: env.ADMIN_USERNAME, password: adminPassword });
    cookie = signedIn.headers.get('set-cookie')!.split(';')[0];
    await db.execute('UPDATE admin_sessions SET expires_at = 0');
    assert.equal((await call('/profile/api/accounts')).status, 401);
    await db.execute('DELETE FROM rate_limits');
    for (let index = 0; index < 8; index++) assert.equal((await call('/profile/api/login', 'POST', { username: 'invalid', password: 'wrong' })).status, 401);
    assert.equal((await call('/profile/api/login', 'POST', { username: env.ADMIN_USERNAME, password: adminPassword })).status, 429);
  });
});

test('existing database migration preserves account data and is repeatable', async t => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'koinly-migrate-'));
  const url = 'file:' + path.join(directory, 'legacy.db').replaceAll('\\', '/');
  let db = createClient({ url });
  t.after(async () => { db.close(); await fs.promises.rm(directory, { recursive: true, force: true, maxRetries: 5, retryDelay: 100 }); });
  await db.executeMultiple("CREATE TABLE users(id TEXT PRIMARY KEY, username TEXT NOT NULL UNIQUE, password_hash TEXT NOT NULL, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL); INSERT INTO users VALUES ('owner', 'existing-owner', 'legacy-hash', 1, 1);");
  db.close();
  for (let run = 0; run < 2; run++) {
    const result = spawnSync(process.execPath, ['scripts/apply-schema.mjs'], { cwd: new URL('..', import.meta.url), env: { ...process.env, TURSO_DATABASE_URL: url, TURSO_AUTH_TOKEN: 'test' }, encoding: 'utf8' });
    assert.equal(result.status, 0, result.stderr);
  }
  db = createClient({ url });
  const row = (await db.execute('SELECT * FROM users')).rows[0];
  assert.equal(row.password_hash, 'legacy-hash'); assert.equal(row.session_version, 0);
  assert.equal(row.recovery_key_hash, null);
  await db.execute('SELECT token_hash FROM admin_sessions');
});
