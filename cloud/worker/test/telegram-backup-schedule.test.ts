import assert from 'node:assert/strict';
import test from 'node:test';

import { nextTelegramBackupDueAt } from '../src/index.ts';

const utc = (value: string) => Date.parse(value);

test('daily Telegram backup schedule respects a fixed device UTC offset', () => {
  const next = nextTelegramBackupDueAt({
    frequency: 'daily',
    hour: 2,
    minute: 0,
    weekday: 7,
    monthDay: 1,
    timezoneOffsetMinutes: 360,
  } as never, utc('2026-09-09T00:00:00Z'));
  assert.equal(new Date(next).toISOString(), '2026-09-09T20:00:00.000Z');
});

test('weekly Telegram backup schedule picks the requested local weekday', () => {
  const next = nextTelegramBackupDueAt({
    frequency: 'weekly',
    hour: 9,
    minute: 30,
    weekday: 5,
    monthDay: 1,
    timezoneOffsetMinutes: 0,
  } as never, utc('2026-09-09T10:00:00Z'));
  assert.equal(new Date(next).toISOString(), '2026-09-11T09:30:00.000Z');
});

test('monthly Telegram backup clamps day 31 to shorter months', () => {
  const next = nextTelegramBackupDueAt({
    frequency: 'monthly',
    hour: 7,
    minute: 0,
    weekday: 1,
    monthDay: 31,
    timezoneOffsetMinutes: 0,
  } as never, utc('2026-09-30T08:00:00Z'));
  assert.equal(new Date(next).toISOString(), '2026-10-31T07:00:00.000Z');
});
