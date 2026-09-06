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
  for (const statement of statements) {
    await client.execute(statement);
  }
  console.log(`Applied Turso schema successfully (${statements.length} statements).`);
} finally {
  client.close();
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
