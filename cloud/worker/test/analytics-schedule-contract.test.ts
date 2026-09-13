import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';

import { nextScheduledUploadDueAt, scheduledClockDistanceMinutes } from '../src/index.ts';

const source = fs.readFileSync(new URL('../src/index.ts', import.meta.url), 'utf8');
const schema = fs.readFileSync(new URL('../schema.sql', import.meta.url), 'utf8');

test('automatic Analytics PDF schedules share the five-minute Worker cron', () => {
  assert.match(source, /\/v1\/analytics-upload\/schedules/);
  assert.match(source, /runDueAnalyticsPdfUploads/);
  assert.match(source, /Automatic uploads must be at least 5 minutes apart/);
  assert.match(source, /Telegram PDF/);
  assert.match(source, /Google Drive PDF/);
  assert.match(source, /Telegram backup/);
  assert.match(source, /buildScheduledAnalyticsPdf/);
  assert.match(source, /buildSimpleTextPdf/);
  assert.match(schema, /CREATE TABLE IF NOT EXISTS analytics_pdf_schedules/);
  assert.match(schema, /destination IN \('telegram', 'googleDrive'\)/);
});

test('generic upload scheduler keeps existing daily, weekly, and monthly semantics', () => {
  const daily = nextScheduledUploadDueAt({
    frequency: 'daily', hour: 3, minute: 10, weekday: 7, monthDay: 1, timezoneOffsetMinutes: 360,
  } as never, Date.parse('2026-09-13T00:00:00Z'));
  assert.equal(new Date(daily).toISOString(), '2026-09-13T21:10:00.000Z');

  const weekly = nextScheduledUploadDueAt({
    frequency: 'weekly', hour: 9, minute: 30, weekday: 1, monthDay: 1, timezoneOffsetMinutes: 0,
  } as never, Date.parse('2026-09-13T10:00:00Z'));
  assert.equal(new Date(weekly).toISOString(), '2026-09-14T09:30:00.000Z');
});


test('five-minute separation handles exact boundaries and midnight wraparound', () => {
  const clock = (hour: number, minute: number) => ({ label: 'test', hour, minute, enabled: true });
  assert.equal(scheduledClockDistanceMinutes(clock(3, 0), clock(3, 5)), 5);
  assert.equal(scheduledClockDistanceMinutes(clock(3, 0), clock(3, 4)), 4);
  assert.equal(scheduledClockDistanceMinutes(clock(23, 58), clock(0, 2)), 4);
  assert.equal(scheduledClockDistanceMinutes(clock(23, 58), clock(0, 3)), 5);
});
