import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';

const source = fs.readFileSync(new URL('../src/index.ts', import.meta.url), 'utf8');
const schema = fs.readFileSync(new URL('../schema.sql', import.meta.url), 'utf8');
const workflow = fs.readFileSync(new URL('../../../.github/workflows/deploy-sync-worker.yml', import.meta.url), 'utf8');

test('analytics PDF upload contract is deployed with Telegram and Google Drive support', () => {
  assert.match(source, /\/v1\/analytics-upload\/telegram/);
  assert.match(source, /\/v1\/analytics-upload\/google-drive/);
  assert.match(source, /google-drive\/callback/);
  assert.match(source, /analyticsUploadAvailable:\s*true/);
  assert.match(source, /drive\.file/);
  assert.match(schema, /CREATE TABLE IF NOT EXISTS analytics_upload_settings/);
  assert.match(schema, /google_refresh_token_encrypted/);
  assert.match(workflow, /analyticsUploadAvailable == true/);
});

test('analytics upload secrets are encrypted and PDF size is bounded', () => {
  assert.match(source, /encryptWorkerSecret\(env\.JWT_SECRET, 'google-drive-client-secret'/);
  assert.match(source, /encryptWorkerSecret\(env\.JWT_SECRET, 'google-drive-refresh-token'/);
  assert.match(source, /analyticsPdfMaxBytes = 10 \* 1024 \* 1024/);
  assert.match(source, /Configure the Telegram bot token and destination in Telegram backup settings first/);
});
