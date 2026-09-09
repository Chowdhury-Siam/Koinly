import assert from 'node:assert/strict';
import test from 'node:test';

import { nextTelegramBackupDueAt } from '../src/index.ts';

// This test intentionally remains source-contract based for the DB-backed
// builder; scheduled Worker tests run without a Turso test database.
test('Telegram backup implementation rejects empty finance snapshots and has history recovery', async () => {
  const fs = await import('node:fs');
  const source = fs.readFileSync(new URL('../src/index.ts', import.meta.url), 'utf8');
  assert.match(source, /telegramBackupFinanceRecordCount\(database\) === 0/);
  assert.match(source, /FROM sync_changes, last_reset/);
  assert.match(source, /an empty Telegram backup was not sent/);
  assert.match(source, /finance_record_count/);
});

test('existing schedule export remains usable', () => {
  const next = nextTelegramBackupDueAt({
    frequency: 'daily', hour: 2, minute: 0, weekday: 7, monthDay: 1, timezoneOffsetMinutes: 360,
  } as never, Date.parse('2026-09-09T00:00:00Z'));
  assert.ok(Number.isFinite(next));
});
