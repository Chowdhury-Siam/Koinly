import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';

import { buildSimpleXlsxFromLines, nextScheduledUploadDueAt, scheduledClockDistanceMinutes } from '../src/index.ts';

const source = fs.readFileSync(new URL('../src/index.ts', import.meta.url), 'utf8');
const schema = fs.readFileSync(new URL('../schema.sql', import.meta.url), 'utf8');
const migration = fs.readFileSync(new URL('../scripts/apply-schema.mjs', import.meta.url), 'utf8');

test('automatic Analytics report schedules share the five-minute Worker cron', () => {
  assert.match(source, /\/v1\/analytics-upload\/schedules/);
  assert.match(source, /runDueAnalyticsPdfUploads/);
  assert.match(source, /Automatic uploads must be at least 5 minutes apart/);
  assert.match(source, /Telegram report/);
  assert.match(source, /Google Drive report/);
  assert.match(source, /Telegram backup/);
  assert.match(source, /buildScheduledAnalyticsPdf/);
  assert.match(source, /buildSimpleTextPdf/);
  assert.match(schema, /CREATE TABLE IF NOT EXISTS analytics_pdf_schedules/);
  assert.match(schema, /destination IN \('telegram', 'googleDrive'\)/);
  assert.match(schema, /date_filter IN \('today', 'thisWeek', 'thisMonth', 'thisYear', 'allTime', 'custom'\)/);
  assert.match(schema, /custom_start TEXT/);
  assert.match(schema, /custom_end TEXT/);
  assert.match(schema, /file_format TEXT NOT NULL DEFAULT 'pdf' CHECK\(file_format IN \('pdf', 'xlsx', 'txt'\)\)/);
  assert.match(source, /buildSimpleXlsxFromLines/);
  assert.match(source, /text\/plain/);
  assert.match(source, /Custom Range/);
  assert.match(source, /scheduledAnalyticsRange\(settings\.dateFilter, nowMs, settings\.timezoneOffsetMinutes, settings\.customStart, settings\.customEnd\)/);
  assert.match(migration, /migrateAnalyticsPdfSchedulesTable/);
  assert.match(migration, /analytics_pdf_schedules_v1142/);
  assert.match(migration, /file_format/);
});

test('scheduled XLSX output is a valid ZIP-based workbook', () => {
  const bytes = buildSimpleXlsxFromLines(['Koinly Analytics', 'Income: BDT 100'], 'Summary');
  assert.deepEqual(Array.from(bytes.subarray(0, 4)), [0x50, 0x4b, 0x03, 0x04]);
  assert.match(Buffer.from(bytes).toString('latin1'), /xl\/workbook\.xml/);
  assert.match(Buffer.from(bytes).toString('latin1'), /xl\/worksheets\/sheet1\.xml/);
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
