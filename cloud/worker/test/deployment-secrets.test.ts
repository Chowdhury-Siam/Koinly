import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import test from 'node:test';
import { deploymentSecrets } from '../scripts/prepare-secrets.mjs';

test('deployment sends only database and JWT runtime secrets; administrator is the first Koinly account', async () => {
  const env = {
    TURSO_DATABASE_URL: 'libsql://local-test.turso.io',
    TURSO_AUTH_TOKEN: 'synthetic-token',
    JWT_SECRET: 'x'.repeat(40),
  };
  const secrets = await deploymentSecrets(env);
  assert.deepEqual(secrets, env);
  assert.equal('ADMIN_USERNAME' in secrets, false);
  assert.equal('ADMIN_PASSWORD' in secrets, false);
  assert.equal('ADMIN_PASSWORD_HASH' in secrets, false);

  await assert.rejects(deploymentSecrets({ ...env, JWT_SECRET: 'too-short' }), /JWT_SECRET/);
  await assert.rejects(deploymentSecrets({ ...env, TURSO_AUTH_TOKEN: '' }), /TURSO_AUTH_TOKEN/);

  const run = (args: string[], values = env) => spawnSync(process.execPath, ['--experimental-transform-types', 'scripts/prepare-secrets.mjs', ...args], {
    cwd: new URL('..', import.meta.url), env: { ...process.env, ...values }, encoding: 'utf8',
  });
  const checked = run(['--check']);
  assert.equal(checked.status, 0, checked.stderr);
  assert.equal(checked.stdout, '');
  const prepared = run([]);
  assert.equal(prepared.status, 0, prepared.stderr);
  assert.deepEqual(JSON.parse(prepared.stdout), env);

  const workflow = fs.readFileSync(new URL('../../../.github/workflows/deploy-sync-worker.yml', import.meta.url), 'utf8');
  assert.match(workflow, /prepare-secrets\.mjs > \.worker-secrets\.json/);
  assert.doesNotMatch(workflow, /ADMIN_USERNAME|ADMIN_PASSWORD/);
});
