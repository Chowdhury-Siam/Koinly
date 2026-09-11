import assert from 'node:assert/strict';
import fs from 'node:fs';
import { DatabaseSync } from 'node:sqlite';

import test from 'node:test';

import ts from 'typescript';
import { profileResponse } from '../src/profile.ts';

// Run the actual handlers against an in-memory SQLite database, without Turso credentials.
const source = fs.readFileSync(new URL('../src/index.ts', import.meta.url), 'utf8')
  .replace("import { createClient, type Client } from '@libsql/client/web';", '')
  .replace("import { profileResponse } from './profile.ts';", '')
  + '\nexport { register, login, refresh, manageAccounts, requireAuth };';
const compiled = ts.transpileModule(source, { compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ES2022 } }).outputText;
const handlers = await import('data:text/javascript;base64,' + Buffer.from(compiled + '\n//# sourceURL=koinly-profile-handlers.js').toString('base64'));
const env = { JWT_SECRET: 'test-secret-with-at-least-32-characters' };
const request = (body: unknown, token?: string) => new Request('https://example.test/v1/profile/accounts', {
  method: body ? 'POST' : 'GET', headers: { 'content-type': 'application/json', ...(token ? { authorization: 'Bearer '+token } : {}) },
  ...(body ? { body: JSON.stringify(body) } : {}),
});

test('profile owner manages accounts, isolated data, credentials and deletion', async () => {
  const sqlite = new DatabaseSync(':memory:');
  const db = {
    async execute(input: any) {
      const statement = sqlite.prepare(typeof input === 'string' ? input : input.sql);
      const args = typeof input === 'string' ? [] : input.args;
      if (statement.columns().length) return { rows: statement.all(...args), rowsAffected: 0 };
      return { rows: [], rowsAffected: Number(statement.run(...args).changes) };
    },
    async transaction() {
      sqlite.exec('BEGIN IMMEDIATE'); let committed = false;
      return { execute: db.execute, async commit() { sqlite.exec('COMMIT'); committed = true; }, close() { if (!committed) sqlite.exec('ROLLBACK'); } };
    },
    async executeMultiple(sql: string) { sqlite.exec(sql); },
    close() { sqlite.close(); },
  };
  try {
    await db.executeMultiple(fs.readFileSync(new URL('../schema.sql', import.meta.url), 'utf8'));
    const owner = await (await handlers.register(request({ username: 'owner', password: 'password-one', deviceId: 'owner-device' }), env, db)).json();
    const ownerAuth = await handlers.requireAuth(request(null, owner.accessToken), env, db);
    const manage = async (body: unknown, auth = ownerAuth) => handlers.manageAccounts(request(body), env, db, auth);
    assert.equal((await (await manage(null)).json()).count, 1);
    await assert.rejects(manage({ action:'create', username:'alice', password:'password-two', currentPassword:'wrong' }), /password is incorrect/);
    const created = await (await manage({ action:'create', username:'alice', password:'password-two', currentPassword:'password-one' })).json();
    assert.match(created.recoveryKey, /^KLY-/);
    await assert.rejects(manage({ action:'create', username:'ALICE', password:'password-two', currentPassword:'password-one' }), /already in use/);
    await assert.rejects(manage({ action:'create', username:'bad name', password:'password-two', currentPassword:'password-one' }), /Username/);
    const listing = await (await manage(null)).json();
    assert.equal(listing.count, 2);
    assert.deepEqual(Object.keys(listing.accounts[0]).sort(), ['created_at','id','username']);
    const alice = await (await handlers.login(request({ username:'alice', password:'password-two', deviceId:'alice-device' }), env, db)).json();
    const aliceAuth = await handlers.requireAuth(request(null, alice.accessToken), env, db);
    await assert.rejects(manage(null, aliceAuth), /Only the Worker owner/);
    await assert.rejects(manage({ action:'delete', id:owner.user.id, currentPassword:'password-one', confirmUsername:'owner' }), /cannot be deleted/);
    await manage({ action:'password', id:alice.user.id, password:'new-password', currentPassword:'password-one' });
    await assert.rejects(handlers.requireAuth(request(null, alice.accessToken), env, db), /Session expired/);
    await assert.rejects(handlers.refresh(request({ refreshToken:alice.refreshToken, deviceId:'alice-device' }), env, db), /invalid or expired/);
    await assert.rejects(handlers.login(request({ username:'alice', password:'password-two', deviceId:'alice-device' }), env, db), /Invalid username or password/);
    const newAlice = await (await handlers.login(request({ username:'alice', password:'new-password', deviceId:'alice-device' }), env, db)).json();
    for (const id of [owner.user.id, alice.user.id]) {
      await db.execute({ sql:"INSERT INTO sync_entities VALUES (?, 'accounts', 'bank', 1, '{}', NULL, 1, 'op')", args:[id] });
      await db.execute({ sql:'INSERT INTO telegram_backup_settings(user_id, updated_at) VALUES (?, 1)', args:[id] });
      await db.execute({ sql:"INSERT INTO processed_operations VALUES (?, 'op', 1, 1)", args:[id] });
      await db.execute({ sql:"INSERT INTO sync_changes(user_id,entity_type,entity_id,operation,version,device_id,operation_id,changed_at) VALUES (?, 'accounts','bank','upsert',1,'device','op',1)", args:[id] });
    }
    await assert.rejects(manage({ action:'delete', id:alice.user.id, currentPassword:'password-one', confirmUsername:'wrong' }), /confirm deletion/);
    await manage({ action:'delete', id:alice.user.id, currentPassword:'password-one', confirmUsername:'alice' });
    for (const table of ['users','devices','refresh_tokens','sync_entities','sync_changes','processed_operations','telegram_backup_settings']) {
      const column = table === 'users' ? 'id' : 'user_id';
      assert.equal((await db.execute({ sql:`SELECT * FROM ${table} WHERE ${column} = ?`, args:[alice.user.id] })).rows.length, 0, table);
      assert.ok((await db.execute({ sql:`SELECT * FROM ${table} WHERE ${column} = ?`, args:[owner.user.id] })).rows.length, 'owner '+table);
    }
    await assert.rejects(handlers.requireAuth(request(null, newAlice.accessToken), env, db), /Session expired/);
    await manage({ action:'password', id:owner.user.id, password:'owner-new-password', currentPassword:'password-one' });
    await assert.rejects(handlers.requireAuth(request(null, owner.accessToken), env, db), /Session expired/);
    await assert.rejects(handlers.requireAuth(request(null), env, db), /Missing access token/);
    await db.execute({ sql:"UPDATE rate_limits SET count = 20 WHERE key = 'login:alice'", args:[] });
    await assert.rejects(handlers.login(request({username:'alice',password:'anything',deviceId:'test-device'}),env,db), /Too many attempts/);
  } finally { db.close(); }
});

test('profile is a private standalone page with a nonce policy and valid browser script', async () => {
  const response = profileResponse(); const html = await response.text();
  assert.match(response.headers.get('cache-control')!, /no-store/);
  assert.match(response.headers.get('content-security-policy')!, /frame-ancestors 'none'/);
  assert.doesNotMatch(html, /__NONCE__|localStorage|innerHTML/);
  const script = html.match(/<script nonce="[^"]+">([\s\S]*?)<\/script>/)![1];
  new Function(script);
  assert.match(html, /autocomplete="current-password"/);
});




