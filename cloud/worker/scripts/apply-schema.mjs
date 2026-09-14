import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { createClient } from '@libsql/client';

const scriptDir = dirname(fileURLToPath(import.meta.url));
const workerDir = dirname(scriptDir);
const schemaPath = join(workerDir, 'schema.sql');

const requiredEnv = ['TURSO_DATABASE_URL', 'TURSO_AUTH_TOKEN'];
const missing = requiredEnv.filter((name) => !process.env[name]);

if (missing.length > 0) {
  console.error(`Missing required environment variable(s): ${missing.join(', ')}`);
  process.exit(1);
}

const sql = await readFile(schemaPath, 'utf8');
const statements = splitSqlStatements(sql);

if (statements.length === 0) {
  console.log('No schema statements found.');
  process.exit(0);
}

const client = createClient({
  url: process.env.TURSO_DATABASE_URL,
  authToken: process.env.TURSO_AUTH_TOKEN,
});

try {
  await migrateLegacyUsersTable(client);
  await migrateAnalyticsUploadSettingsTable(client);
  await migrateAnalyticsPdfSchedulesTable(client);
  for (const statement of statements) {
    await client.execute(statement);
  }
  await migrateLegacyUsersTable(client);
  await migrateAnalyticsUploadSettingsTable(client);
  await migrateAnalyticsPdfSchedulesTable(client);
  console.log(`Applied Turso schema successfully (${statements.length} statements).`);
} finally {
  client.close();
}

async function migrateLegacyUsersTable(client) {
  const table = (await client.execute("SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'users'")).rows[0];
  if (!table) return;

  let columns = await userColumns(client);
  if (columns.has('email') && !columns.has('username')) {
    await client.execute('ALTER TABLE users RENAME COLUMN email TO username');
    columns = await userColumns(client);

    const rows = (await client.execute('SELECT id, username FROM users')).rows;
    for (const row of rows) {
      const legacy = String(row.username ?? '');
      const migrated = legacyUsername(legacy);
      if (migrated !== legacy) {
        await client.execute({
          sql: 'UPDATE users SET username = ?, updated_at = ? WHERE id = ?',
          args: [migrated, Date.now(), String(row.id)],
        });
      }
    }
    console.log('Migrated legacy email login column to username.');
  }

  columns = await userColumns(client);
  if (!columns.has('recovery_key_hash')) {
    await client.execute('ALTER TABLE users ADD COLUMN recovery_key_hash TEXT');
    console.log('Added recovery-key support to existing users table.');
  }
  if (!columns.has('session_version')) {
    await client.execute('ALTER TABLE users ADD COLUMN session_version INTEGER NOT NULL DEFAULT 0');
    console.log('Added account session revocation support.');
  }
}


async function migrateAnalyticsUploadSettingsTable(client) {
  const table = (await client.execute("SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'analytics_upload_settings'")).rows[0];
  if (!table) return;
  const rows = (await client.execute("PRAGMA table_info('analytics_upload_settings')")).rows;
  const columns = new Set(rows.map((row) => String(row.name)));
  if (!columns.has('google_folder_path')) {
    await client.execute("ALTER TABLE analytics_upload_settings ADD COLUMN google_folder_path TEXT NOT NULL DEFAULT 'Koinly Analytics'");
    console.log('Added configurable Google Drive upload folder support.');
  }
}

async function migrateAnalyticsPdfSchedulesTable(client) {
  const table = (await client.execute("SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'analytics_pdf_schedules'")).rows[0];
  if (!table) return;

  const tableSql = String(table.sql ?? '');
  const rows = (await client.execute("PRAGMA table_info('analytics_pdf_schedules')")).rows;
  const columns = new Set(rows.map((row) => String(row.name)));
  const supportsCustom = tableSql.includes("'custom'") && columns.has('custom_start') && columns.has('custom_end');
  const supportsFormats = columns.has('file_format') && tableSql.includes("'xlsx'") && tableSql.includes("'txt'");
  if (supportsCustom && supportsFormats) return;

  const customStart = columns.has('custom_start') ? 'custom_start' : 'NULL';
  const customEnd = columns.has('custom_end') ? 'custom_end' : 'NULL';
  const fileFormat = columns.has('file_format') ? 'file_format' : "'pdf'";
  await client.batch([
    'DROP INDEX IF EXISTS idx_analytics_pdf_schedule_due',
    'DROP TABLE IF EXISTS analytics_pdf_schedules_v1142',
    `CREATE TABLE analytics_pdf_schedules_v1142 (
      user_id TEXT NOT NULL,
      destination TEXT NOT NULL CHECK(destination IN ('telegram', 'googleDrive')),
      enabled INTEGER NOT NULL DEFAULT 0 CHECK(enabled IN (0, 1)),
      report_variant TEXT NOT NULL DEFAULT 'summary' CHECK(report_variant IN ('summary', 'transactionHistory')),
      file_format TEXT NOT NULL DEFAULT 'pdf' CHECK(file_format IN ('pdf', 'xlsx', 'txt')),
      date_filter TEXT NOT NULL DEFAULT 'thisMonth' CHECK(date_filter IN ('today', 'thisWeek', 'thisMonth', 'thisYear', 'allTime', 'custom')),
      custom_start TEXT,
      custom_end TEXT,
      frequency TEXT NOT NULL DEFAULT 'daily' CHECK(frequency IN ('daily', 'weekly', 'monthly')),
      hour INTEGER NOT NULL DEFAULT 3 CHECK(hour BETWEEN 0 AND 23),
      minute INTEGER NOT NULL DEFAULT 0 CHECK(minute BETWEEN 0 AND 59),
      weekday INTEGER NOT NULL DEFAULT 7 CHECK(weekday BETWEEN 1 AND 7),
      month_day INTEGER NOT NULL DEFAULT 1 CHECK(month_day BETWEEN 1 AND 31),
      timezone_offset_minutes INTEGER NOT NULL DEFAULT 0 CHECK(timezone_offset_minutes BETWEEN -840 AND 840),
      next_due_at INTEGER,
      last_sent_at INTEGER,
      last_attempt_at INTEGER,
      last_error TEXT,
      updated_at INTEGER NOT NULL,
      PRIMARY KEY(user_id, destination),
      FOREIGN KEY(user_id) REFERENCES users(id)
    )`,
    `INSERT INTO analytics_pdf_schedules_v1142(
        user_id, destination, enabled, report_variant, file_format, date_filter, custom_start, custom_end, frequency,
        hour, minute, weekday, month_day, timezone_offset_minutes, next_due_at,
        last_sent_at, last_attempt_at, last_error, updated_at
      )
      SELECT user_id, destination, enabled, report_variant, ${fileFormat}, date_filter, ${customStart}, ${customEnd}, frequency,
        hour, minute, weekday, month_day, timezone_offset_minutes, next_due_at,
        last_sent_at, last_attempt_at, last_error, updated_at
      FROM analytics_pdf_schedules`,
    'DROP TABLE analytics_pdf_schedules',
    'ALTER TABLE analytics_pdf_schedules_v1142 RENAME TO analytics_pdf_schedules',
    'CREATE INDEX IF NOT EXISTS idx_analytics_pdf_schedule_due ON analytics_pdf_schedules(enabled, next_due_at)',
  ], 'write');
  console.log('Upgraded Analytics report schedules for PDF, XLSX, TXT, and centered custom date ranges.');
}

async function userColumns(client) {
  const rows = (await client.execute("PRAGMA table_info('users')")).rows;
  return new Set(rows.map((row) => String(row.name)));
}

function legacyUsername(value) {
  const raw = String(value ?? '').trim().toLowerCase();
  const localPart = raw.includes('@') ? raw.split('@')[0] : raw;
  let username = localPart
    .replace(/[^a-z0-9._-]+/g, '_')
    .replace(/^[._-]+|[._-]+$/g, '')
    .slice(0, 32);
  if (!username) username = 'koinly_owner';
  while (username.length < 3) username += '_owner';
  return username.slice(0, 32).replace(/[._-]+$/g, '') || 'koinly_owner';
}

function splitSqlStatements(source) {
  const statements = [];
  let current = '';
  let quote = null;
  let inLineComment = false;

  for (let i = 0; i < source.length; i += 1) {
    const char = source[i];
    const next = source[i + 1];

    if (inLineComment) {
      if (char === '\n') {
        inLineComment = false;
        current += char;
      }
      continue;
    }

    if (!quote && char === '-' && next === '-') {
      inLineComment = true;
      i += 1;
      continue;
    }

    current += char;

    if (quote) {
      if (char === quote) {
        if (next === quote) {
          current += next;
          i += 1;
        } else {
          quote = null;
        }
      }
      continue;
    }

    if (char === '\'' || char === '"') {
      quote = char;
      continue;
    }

    if (char === ';') {
      const statement = current.trim();
      if (statement) statements.push(statement);
      current = '';
    }
  }

  const trailing = current.trim();
  if (trailing) statements.push(trailing);
  return statements;
}
