import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const source = readFileSync(new URL('../src/index.ts', import.meta.url), 'utf8');
const schema = readFileSync(new URL('../schema.sql', import.meta.url), 'utf8');

test('deployment recovery is encrypted and restricted to the first sync account', () => {
  assert.match(source, /\/v1\/deployment-recovery\/profile/);
  assert.match(source, /requireDeploymentRecoveryOwner/);
  assert.match(source, /deployment_owner_user_id/);
  assert.match(source, /encryptWorkerSecret\([\s\S]*deployment-recovery-v1/);
  assert.match(source, /decryptWorkerSecret\([\s\S]*deployment-recovery-v1/);
  assert.match(source, /deployment_recovery_ciphertext/);
  assert.match(source, /deployment_recovery_iv/);
  assert.match(source, /deploymentRecoveryAvailable/);
  assert.match(source, /version: 2/);
  assert.doesNotMatch(source, /adminUsername|adminPasswordHash/);
  assert.doesNotMatch(source, /deployment_recovery_plaintext/);
});

test('schema upgrades existing workers with the oldest account as deployment owner', () => {
  assert.match(schema, /deployment_owner_user_id/);
  assert.match(schema, /ORDER BY created_at ASC, id ASC/);
});
