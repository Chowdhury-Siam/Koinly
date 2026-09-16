import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import test from 'node:test';
import { createClient } from '@libsql/client';
import { profile, register, login, requireAuth } from '../src/index.ts';
import { deploymentSecrets } from '../scripts/prepare-secrets.mjs';

const origin = 'https://worker.example';
const schema = fs.readFileSync(new URL('../schema.sql', import.meta.url), 'utf8');

test('first sync account owns the profile portal and account lifecycle', async t => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'koinly-profile-'));
  const databaseUrl = 'file:' + path.join(directory, 'test.db').replaceAll('\\', '/');
  const connect = () => createClient({ url: databaseUrl });
  const db = connect();
  t.after(async () => {
    db.close();
    await fs.promises.rm(directory, { recursive: true, force: true, maxRetries: 5, retryDelay: 100 });
  });
  await db.executeMultiple(schema);
  const env = await deploymentSecrets({
    TURSO_DATABASE_URL: databaseUrl,
    TURSO_AUTH_TOKEN: 'local-test',
    JWT_SECRET: 'x'.repeat(40),
  });

  let cookie = '';
  const request = (route: string, method = 'GET', body?: unknown, headers: Record<string, string> = {}) => new Request(origin + route, {
    method,
    headers: { origin, 'x-profile-request': '1', 'content-type': 'application/json', cookie, ...headers },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const call = (route: string, method = 'GET', body?: unknown, headers: Record<string, string> = {}) =>
    profile(request(route, method, body, headers), env, connect);

  await t.test('empty Worker directs setup to the first app account', async () => {
    const page = await call('/profile');
    assert.equal(page.status, 503);
    const html = await page.text();
    assert.match(html, /first Koinly account/i);
    assert.match(html, /automatically becomes the Worker administrator/i);
    assert.match(html, /#0F1216/i);
    assert.match(html, /#00BD91/i);
    assert.equal((await call('/profile/api/accounts')).status, 503);
  });

  let administratorId = '';
  await t.test('the first app registration becomes the immutable administrator identity', async () => {
    const first = await register(
      request('/v1/auth/register', 'POST', { username: 'First-Owner', password: 'password123', deviceId: 'first-device' }),
      env,
      db,
    );
    assert.equal(first.status, 200);
    const row = (await db.execute("SELECT id, username FROM users ORDER BY created_at ASC, id ASC LIMIT 1")).rows[0];
    administratorId = String(row.id);
    assert.equal(row.username, 'first-owner');
    assert.equal((await db.execute("SELECT value FROM worker_state WHERE key = 'deployment_owner_user_id'")).rows[0].value, administratorId);
    await assert.rejects(
      register(request('/v1/auth/register', 'POST', { username: 'second-owner', password: 'password123', deviceId: 'second-device' }), env, db),
      /administrator/,
    );
  });

  await t.test('profile login uses that first account and exposes the updated account UI', async () => {
    const credentials = { username: 'first-owner', password: 'password123' };
    assert.equal((await call('/profile/api/login', 'POST', credentials, { origin: 'https://evil.example' })).status, 403);
    assert.equal((await call('/profile/api/login', 'POST', { ...credentials, password: 'wrong' })).status, 401);
    const response = await call('/profile/api/login', 'POST', credentials);
    assert.equal(response.status, 200);
    const setCookie = response.headers.get('set-cookie')!;
    assert.match(setCookie, /^__Host-koinly-admin=/);
    for (const flag of ['HttpOnly', 'Secure', 'SameSite=Strict', 'Path=/', 'Max-Age=3600']) assert.ok(setCookie.includes(flag));
    cookie = setCookie.split(';')[0];

    const dashboard = await call('/profile');
    assert.equal(dashboard.status, 200);
    const html = await dashboard.text();
    assert.match(html, /id="dashboard"/);
    assert.match(html, /id="username-dialog"/);
    assert.match(html, /Change username/);
    assert.match(html, /First-account administrator/);
    assert.match(html, /administrator-badge/);
    assert.doesNotMatch(html, /ADMIN_USERNAME|ADMIN_PASSWORD/);

    const protectedRequest = await call('/profile/api/accounts', 'GET', undefined, { cookie: '' });
    assert.equal(protectedRequest.status, 401);
    const listed = await (await call('/profile/api/accounts')).json();
    assert.equal(listed.total, 1);
    assert.equal(listed.accounts[0].id, administratorId);
    assert.equal(listed.accounts[0].username, 'first-owner');
    assert.equal(listed.accounts[0].isAdministrator, true);
    assert.equal((await call('/profile/api/accounts/' + administratorId, 'DELETE')).status, 409);
  });

  let aliceId = '';
  await t.test('administrator can create and rename user accounts without changing account identity', async () => {
    assert.equal((await call('/profile/api/accounts', 'POST', { username: 'Alice', password: 'password123' })).status, 201);
    const listed = await (await call('/profile/api/accounts')).json();
    const alice = listed.accounts.find((account: any) => account.username === 'alice');
    assert.ok(alice);
    aliceId = alice.id;
    assert.equal(alice.isAdministrator, false);

    const renamed = await call('/profile/api/accounts/' + aliceId + '/username', 'POST', { username: 'Alice.Renamed' });
    assert.equal(renamed.status, 200);
    assert.match(await renamed.text(), /Username changed/);
    const aliceRow = (await db.execute({ sql: 'SELECT id, username FROM users WHERE id = ?', args: [aliceId] })).rows[0];
    assert.equal(aliceRow.id, aliceId);
    assert.equal(aliceRow.username, 'alice.renamed');

    assert.equal((await call('/profile/api/accounts/' + aliceId + '/username', 'POST', { username: 'FIRST-OWNER' })).status, 409);
    assert.equal((await call('/profile/api/accounts/no-such-id/username', 'POST', { username: 'unused-name' })).status, 404);
    await assert.rejects(login(request('/v1/auth/login', 'POST', { username: 'alice', password: 'password123', deviceId: 'alice-device' }), env, db), /Invalid username or password/);
    const loginResponse = await login(request('/v1/auth/login', 'POST', { username: 'alice.renamed', password: 'password123', deviceId: 'alice-device' }), env, db);
    assert.equal(loginResponse.status, 200);
  });

  await t.test('administrator username can change and current portal session remains attached to its user id', async () => {
    const renamed = await call('/profile/api/accounts/' + administratorId + '/username', 'POST', { username: 'Owner.Main' });
    assert.equal(renamed.status, 200);
    assert.equal((await call('/profile/api/accounts')).status, 200);
    assert.equal((await db.execute("SELECT value FROM worker_state WHERE key = 'deployment_owner_user_id'")).rows[0].value, administratorId);
    assert.equal((await call('/profile/api/login', 'POST', { username: 'first-owner', password: 'password123' })).status, 401);
    const newLogin = await call('/profile/api/login', 'POST', { username: 'owner.main', password: 'password123' });
    assert.equal(newLogin.status, 200);
    cookie = newLogin.headers.get('set-cookie')!.split(';')[0];
  });

  await t.test('password change revokes account sessions and profile session when changing the administrator', async () => {
    const aliceSession = await (await login(request('/v1/auth/login', 'POST', { username: 'alice.renamed', password: 'password123', deviceId: 'alice-device-2' }), env, db)).json();
    await requireAuth(request('/v1/sync/status', 'GET', undefined, { authorization: 'Bearer ' + aliceSession.accessToken }), env, db);
    assert.equal((await call('/profile/api/accounts/' + aliceId + '/password', 'POST', { password: 'new-password123' })).status, 200);
    await assert.rejects(requireAuth(request('/v1/sync/status', 'GET', undefined, { authorization: 'Bearer ' + aliceSession.accessToken }), env, db), /revoked/);
    await assert.rejects(login(request('/v1/auth/login', 'POST', { username: 'alice.renamed', password: 'password123', deviceId: 'alice-device-3' }), env, db), /Invalid username or password/);
    assert.equal((await login(request('/v1/auth/login', 'POST', { username: 'alice.renamed', password: 'new-password123', deviceId: 'alice-device-3' }), env, db)).status, 200);

    const oldAdminCookie = cookie;
    assert.equal((await call('/profile/api/accounts/' + administratorId + '/password', 'POST', { password: 'administrator-new-password' })).status, 200);
    assert.equal((await call('/profile/api/accounts', 'GET', undefined, { cookie: oldAdminCookie })).status, 401);
    const relogin = await call('/profile/api/login', 'POST', { username: 'owner.main', password: 'administrator-new-password' });
    assert.equal(relogin.status, 200);
    cookie = relogin.headers.get('set-cookie')!.split(';')[0];
  });

  await t.test('only non-administrator accounts can be deleted and registration stays closed', async () => {
    assert.equal((await call('/profile/api/accounts/' + aliceId, 'DELETE')).status, 200);
    assert.equal((await call('/profile/api/accounts/' + aliceId, 'DELETE')).status, 404);
    assert.equal((await call('/profile/api/accounts/' + administratorId, 'DELETE')).status, 409);
    await assert.rejects(
      register(request('/v1/auth/register', 'POST', { username: 'outsider', password: 'password123', deviceId: 'outsider-device' }), env, db),
      /administrator/,
    );
    const listed = await (await call('/profile/api/accounts')).json();
    assert.equal(listed.total, 1);
    assert.equal(listed.accounts[0].username, 'owner.main');
    assert.equal(listed.accounts[0].isAdministrator, true);
  });

  await t.test('portal security rejects tampered sessions and JWT-secret rotation', async () => {
    assert.equal((await call('/profile/api/accounts', 'GET', undefined, { cookie: cookie + 'tamper' })).status, 401);
    assert.equal((await profile(request('/profile/api/accounts'), { ...env, JWT_SECRET: 'y'.repeat(40) }, connect)).status, 401);
    const signedOut = await call('/profile/api/logout', 'POST', {});
    assert.match(signedOut.headers.get('set-cookie')!, /Max-Age=0/);
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
