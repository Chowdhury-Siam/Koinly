import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import test from 'node:test';
import { deploymentSecrets } from '../scripts/prepare-secrets.mjs';
import { verifyPassword } from '../src/index.ts';

test('deployment accepts ADMIN_PASSWORD and sends only its salted hash to the Worker', async () => {
  const env = {
    TURSO_DATABASE_URL: 'libsql://local-test.turso.io', TURSO_AUTH_TOKEN: 'synthetic-token', JWT_SECRET: 'x'.repeat(40),
    ADMIN_USERNAME: 'worker-admin', ADMIN_PASSWORD: 'Test-🔒-password\n"quotes" $variables `commands`',
  };
  const secrets = await deploymentSecrets(env);
  assert.equal('ADMIN_PASSWORD' in secrets, false);
  assert.equal(await verifyPassword(env.ADMIN_PASSWORD, secrets.ADMIN_PASSWORD_HASH), true);
  assert.equal(await verifyPassword('wrong-password', secrets.ADMIN_PASSWORD_HASH), false);
  assert.notEqual((await deploymentSecrets(env)).ADMIN_PASSWORD_HASH, secrets.ADMIN_PASSWORD_HASH);
  assert.equal(secrets.JWT_SECRET, env.JWT_SECRET);
  for (const ADMIN_PASSWORD of ['', 'too-short', 'x'.repeat(257)]) await assert.rejects(deploymentSecrets({ ...env, ADMIN_PASSWORD }), /ADMIN_PASSWORD/);
  for (const ADMIN_USERNAME of ['', 'ab', 'Mixed-Case', '_invalid']) await assert.rejects(deploymentSecrets({ ...env, ADMIN_USERNAME }), /ADMIN_USERNAME/);

  const run = (args: string[], values = env) => spawnSync(process.execPath, ['--experimental-transform-types', 'scripts/prepare-secrets.mjs', ...args], {
    cwd: new URL('..', import.meta.url), env: { ...process.env, ...values }, encoding: 'utf8',
  });
  const checked = run(['--check']);
  assert.equal(checked.status, 0, checked.stderr); assert.equal(checked.stdout, '');
  const prepared = run([]);
  assert.equal(prepared.status, 0, prepared.stderr);
  const uploaded = JSON.parse(prepared.stdout);
  assert.equal('ADMIN_PASSWORD' in uploaded, false);
  assert.equal(await verifyPassword(env.ADMIN_PASSWORD, uploaded.ADMIN_PASSWORD_HASH), true);
  assert.equal(prepared.stdout.includes(env.ADMIN_PASSWORD), false);
  assert.equal(prepared.stderr.includes(env.ADMIN_PASSWORD), false);
  const invalid = run([], { ...env, ADMIN_PASSWORD: 'bad-value' });
  assert.equal(invalid.status, 1); assert.equal(invalid.stdout, '');
  assert.match(invalid.stderr, /ADMIN_PASSWORD/); assert.doesNotMatch(invalid.stderr, /bad-value/);

  const workflow = fs.readFileSync(new URL('../../../.github/workflows/deploy-sync-worker.yml', import.meta.url), 'utf8');
  assert.match(workflow, /ADMIN_PASSWORD: \$\{\{ secrets.ADMIN_PASSWORD \}\}/);
  assert.doesNotMatch(workflow, /secrets\.ADMIN_PASSWORD_HASH/);
  assert.match(workflow, /prepare-secrets\.mjs > \.worker-secrets\.json/);
  assert.match(workflow, /unset ADMIN_PASSWORD/);
});
