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
  for (const statement of statements) {
    await client.execute(statement);
  }
  await migrateLegacyUsersTable(client);
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
