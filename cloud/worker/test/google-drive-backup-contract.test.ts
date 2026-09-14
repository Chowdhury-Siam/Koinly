import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';

const source = fs.readFileSync(new URL('../src/index.ts', import.meta.url), 'utf8');
const schema = fs.readFileSync(new URL('../schema.sql', import.meta.url), 'utf8');
const workflow = fs.readFileSync(new URL('../../../.github/workflows/deploy-sync-worker.yml', import.meta.url), 'utf8');

test('Google Drive cloud backup has settings, manual upload, cron delivery, and schema', () => {
  assert.match(source, /\/v1\/google-drive-backup\/settings/);
  assert.match(source, /\/v1\/google-drive-backup\/send-now/);
  assert.match(source, /runDueGoogleDriveBackups/);
  assert.match(source, /buildGoogleDriveBackupFile/);
  assert.match(source, /resolveGoogleBackupFolder/);
  assert.match(source, /Koinly Backup/);
  assert.match(source, /googleDriveBackupAvailable:\s*true/);
  assert.match(schema, /CREATE TABLE IF NOT EXISTS google_drive_backup_settings/);
  assert.match(workflow, /googleDriveBackupAvailable == true/);
});

test('all automatic external uploads participate in the five-minute guard', () => {
  assert.match(source, /label: 'Telegram report'/);
  assert.match(source, /label: 'Google Drive report'/);
  assert.match(source, /label: 'Telegram backup'/);
  assert.match(source, /label: 'Google Drive backup'/);
  assert.match(source, /scheduledClockDistanceMinutes/);
});
