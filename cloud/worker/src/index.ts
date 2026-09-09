import { createClient, type Client, type Transaction } from '@libsql/client/web';

type Env = {
  TURSO_DATABASE_URL: string;
  TURSO_AUTH_TOKEN: string;
  JWT_SECRET: string;
  TELEGRAM_BOT_TOKEN: string;
  REGISTRATION_KEY_CHAT_ID: string;
  REGISTRATION_ADMIN_SECRET: string;
  ACCESS_TOKEN_TTL_SECONDS?: string;
  REFRESH_TOKEN_TTL_SECONDS?: string;
  MAX_SYNC_BATCH_SIZE?: string;
  MAX_SYNC_REPLACE_SIZE?: string;
  REGISTRATION_KEY_TTL_SECONDS?: string;
};

type AuthContext = {
  userId: string;
  email: string;
  deviceId: string;
};

type SyncOperation = {
  operationId: string;
  entityType: string;
  entityId: string;
  operation: 'upsert' | 'delete';
  payload?: unknown;
  baseVersion?: number;
  clientUpdatedAt?: number;
};

const enc = new TextEncoder();
const requiredTables = [
  'users',
  'refresh_tokens',
  'devices',
  'sync_entities',
  'sync_changes',
  'processed_operations',
  'rate_limits',
  'registration_keys',
  'telegram_backup_settings',
];

export default {
  async fetch(request: Request, env: Env, context: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);
    let db: Client | undefined;

    try {
      if (request.method === 'OPTIONS') return cors(new Response(null, { status: 204 }));
      if (request.method === 'GET' && url.pathname === '/') return rootResponse(env);
      if (request.method === 'GET' && url.pathname === '/health') return healthResponse(env);

      validateWorkerConfig(env);
      db = createClient({ url: env.TURSO_DATABASE_URL, authToken: env.TURSO_AUTH_TOKEN });

      if (request.method === 'POST' && url.pathname === '/v1/auth/register') {
        if (registrationMode(env) === 'invite-key') await ensureActiveRegistrationKey(env, db, context);
        return await register(request, env, db, context);
      }
      if (request.method === 'POST' && url.pathname === '/v1/auth/login') return await login(request, env, db);
      if (request.method === 'POST' && url.pathname === '/v1/auth/refresh') return await refresh(request, env, db);
      if (url.pathname.startsWith('/v1/admin/registration-key/')) {
        return await registrationKeyAdmin(request, url, env, db, context);
      }

      const auth = await requireAuth(request, env);
      if (request.method === 'POST' && url.pathname === '/v1/auth/logout') return await logout(request, db, auth);
      if (request.method === 'POST' && url.pathname === '/v1/sync/initial') return await initialSync(request, db, auth);
      if (request.method === 'POST' && url.pathname === '/v1/sync/push') return await push(request, env, db, auth);
      if (request.method === 'POST' && url.pathname === '/v1/sync/replace') return await replaceAll(request, env, db, auth);
      if (request.method === 'GET' && url.pathname === '/v1/sync/pull') return await pull(url, env, db, auth);
      if (request.method === 'GET' && url.pathname === '/v1/sync/status') return await status(db, auth);
      if (request.method === 'GET' && url.pathname === '/v1/telegram-backup/settings') return await telegramBackupSettings(env, db, auth);
      if (request.method === 'POST' && url.pathname === '/v1/telegram-backup/settings') return await saveTelegramBackupSettings(request, env, db, auth);
      if (request.method === 'POST' && url.pathname === '/v1/telegram-backup/test') return await testTelegramBackup(request, env, db, auth);
      if (request.method === 'POST' && url.pathname === '/v1/telegram-backup/send-now') return await sendTelegramBackupNow(env, db, auth);

      return json({ error: 'Not found.' }, 404);
    } catch (error) {
      const statusCode = error instanceof HttpError ? error.status : 500;
      const message = error instanceof HttpError ? error.message : 'Internal server error.';
      if (!(error instanceof HttpError)) {
        console.error('Unhandled sync worker error', {
          path: url.pathname,
          method: request.method,
          error: databaseErrorMessage(error),
        });
      }
      return json({ error: message }, statusCode);
    } finally {
      db?.close();
    }
  },

  async scheduled(_controller: ScheduledController, env: Env, _context: ExecutionContext): Promise<void> {
    // The managed/default Worker intentionally never runs user Telegram backup
    // jobs. This scheduler is used only by the self-hosted first-owner Worker.
    if (registrationMode(env) !== 'first-user') return;
    validateWorkerConfig(env);
    const db = createClient({ url: env.TURSO_DATABASE_URL, authToken: env.TURSO_AUTH_TOKEN });
    try {
      await runDueTelegramBackups(env, db);
    } catch (error) {
      console.error('Scheduled Telegram backup run failed', databaseErrorMessage(error));
    } finally {
      db.close();
    }
  },
};

type TelegramBackupFrequency = 'daily' | 'weekly' | 'monthly';

type TelegramBackupSettings = {
  userId: string;
  enabled: boolean;
  tokenConfigured: boolean;
  encryptedToken: string;
  tokenIv: string;
  chatId: string;
  frequency: TelegramBackupFrequency;
  hour: number;
  minute: number;
  weekday: number;
  monthDay: number;
  timezoneOffsetMinutes: number;
  nextDueAt: number | null;
  lastSentAt: number | null;
  lastAttemptAt: number | null;
  lastError: string | null;
};

const telegramBackupEntityTables = [
  'accounts',
  'categories',
  'planned_purchases',
  'transactions',
  'budgets',
  'budget_accounts',
  'budget_categories',
  'loan_contacts',
  'loans',
  'loan_payments',
] as const;

// The mobile app currently uses this compatibility key for .koinlybackup files.
// Keep the Worker encoder byte-for-byte compatible so a Telegram backup can be
// restored directly by Koinly without a conversion step.
const koinlyBackupCompatibilityKey = 'YOUR_SECRET_PASSWORD';

function requireSelfHostedTelegramBackup(env: Env): void {
  if (registrationMode(env) !== 'first-user') {
    throw new HttpError(403, 'Telegram cloud backup is available only on a self-hosted Sync Worker.');
  }
}

async function telegramBackupSettings(env: Env, db: Client, auth: AuthContext): Promise<Response> {
  requireSelfHostedTelegramBackup(env);
  const settings = await readTelegramBackupSettings(db, auth.userId);
  return privateJson({ ok: true, settings: publicTelegramBackupSettings(settings) });
}

async function saveTelegramBackupSettings(request: Request, env: Env, db: Client, auth: AuthContext): Promise<Response> {
  requireSelfHostedTelegramBackup(env);
  const body = await readJson(request);
  const existing = await readTelegramBackupSettings(db, auth.userId);
  const enabled = body.enabled === true;
  const botToken = String(body.botToken ?? '').trim();
  const chatId = normalizeTelegramChatId(body.chatId ?? existing.chatId);
  const frequency = normalizeTelegramBackupFrequency(body.frequency ?? existing.frequency);
  const hour = integerInRange(body.hour, existing.hour, 0, 23, 'hour');
  const minute = integerInRange(body.minute, existing.minute, 0, 59, 'minute');
  const weekday = integerInRange(body.weekday, existing.weekday, 1, 7, 'weekday');
  const monthDay = integerInRange(body.monthDay, existing.monthDay, 1, 31, 'monthDay');
  const timezoneOffsetMinutes = integerInRange(
    body.timezoneOffsetMinutes,
    existing.timezoneOffsetMinutes,
    -840,
    840,
    'timezoneOffsetMinutes',
  );

  let encryptedToken = existing.encryptedToken;
  let tokenIv = existing.tokenIv;
  if (botToken) {
    validateTelegramBotToken(botToken);
    const encrypted = await encryptTelegramBotToken(env.JWT_SECRET, botToken);
    encryptedToken = encrypted.ciphertext;
    tokenIv = encrypted.iv;
  }

  if (enabled && !encryptedToken) throw new HttpError(400, 'Enter a Telegram bot token before enabling backups.');
  if (enabled && !chatId) throw new HttpError(400, 'Enter a Telegram group or channel Chat ID before enabling backups.');

  const nextDueAt = enabled
    ? nextTelegramBackupDueAt({ frequency, hour, minute, weekday, monthDay, timezoneOffsetMinutes }, Date.now())
    : null;
  const now = Date.now();
  await db.execute({
    sql: `INSERT INTO telegram_backup_settings(
            user_id, enabled, bot_token_encrypted, bot_token_iv, chat_id, frequency,
            hour, minute, weekday, month_day, timezone_offset_minutes, next_due_at,
            last_sent_at, last_attempt_at, last_error, updated_at
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT(user_id) DO UPDATE SET
            enabled = excluded.enabled,
            bot_token_encrypted = excluded.bot_token_encrypted,
            bot_token_iv = excluded.bot_token_iv,
            chat_id = excluded.chat_id,
            frequency = excluded.frequency,
            hour = excluded.hour,
            minute = excluded.minute,
            weekday = excluded.weekday,
            month_day = excluded.month_day,
            timezone_offset_minutes = excluded.timezone_offset_minutes,
            next_due_at = excluded.next_due_at,
            last_error = NULL,
            updated_at = excluded.updated_at`,
    args: [
      auth.userId,
      enabled ? 1 : 0,
      encryptedToken || null,
      tokenIv || null,
      chatId,
      frequency,
      hour,
      minute,
      weekday,
      monthDay,
      timezoneOffsetMinutes,
      nextDueAt,
      existing.lastSentAt,
      existing.lastAttemptAt,
      null,
      now,
    ],
  });
  const saved = await readTelegramBackupSettings(db, auth.userId);
  return privateJson({ ok: true, settings: publicTelegramBackupSettings(saved) });
}

async function testTelegramBackup(request: Request, env: Env, db: Client, auth: AuthContext): Promise<Response> {
  requireSelfHostedTelegramBackup(env);
  const body = await readJson(request);
  const settings = await readTelegramBackupSettings(db, auth.userId);
  const suppliedToken = String(body.botToken ?? '').trim();
  const token = suppliedToken || (settings.encryptedToken
    ? await decryptTelegramBotToken(env.JWT_SECRET, settings.encryptedToken, settings.tokenIv)
    : '');
  const suppliedChatId = String(body.chatId ?? '').trim();
  const chatId = normalizeTelegramChatId(suppliedChatId || settings.chatId);
  if (!token) throw new HttpError(400, 'Enter or save a Telegram bot token first.');
  validateTelegramBotToken(token);
  if (!chatId) throw new HttpError(400, 'Enter a Telegram group or channel Chat ID first.');

  await telegramApiJson(token, 'getMe', {});
  await telegramApiJson(token, 'sendMessage', {
    chat_id: chatId,
    text: 'Koinly self-hosted Telegram backup is connected.',
    disable_web_page_preview: true,
  });
  return privateJson({ ok: true });
}

async function sendTelegramBackupNow(env: Env, db: Client, auth: AuthContext): Promise<Response> {
  requireSelfHostedTelegramBackup(env);
  const settings = await readTelegramBackupSettings(db, auth.userId);
  if (!settings.encryptedToken || !settings.chatId) {
    throw new HttpError(400, 'Save the Telegram bot token and destination first.');
  }
  const result = await deliverTelegramBackupForUser(env, db, auth.userId, settings, false);
  return privateJson({ ok: true, ...result, settings: publicTelegramBackupSettings(await readTelegramBackupSettings(db, auth.userId)) });
}

async function runDueTelegramBackups(env: Env, db: Client): Promise<void> {
  const now = Date.now();
  const rows = (await db.execute({
    sql: `SELECT user_id, enabled, bot_token_encrypted, bot_token_iv, chat_id, frequency,
                 hour, minute, weekday, month_day, timezone_offset_minutes, next_due_at,
                 last_sent_at, last_attempt_at, last_error
          FROM telegram_backup_settings
          WHERE enabled = 1 AND next_due_at IS NOT NULL AND next_due_at <= ?
          ORDER BY next_due_at
          LIMIT 20`,
    args: [now],
  })).rows;

  for (const row of rows) {
    const settings = telegramBackupSettingsFromRow(row);
    if (!settings.encryptedToken || !settings.chatId || settings.nextDueAt == null) continue;
    const claimedDueAt = settings.nextDueAt;
    const nextDueAt = nextTelegramBackupDueAt(settings, now + 60_000);
    const claimed = await db.execute({
      sql: `UPDATE telegram_backup_settings
            SET next_due_at = ?, last_attempt_at = ?, updated_at = ?
            WHERE user_id = ? AND enabled = 1 AND next_due_at = ?`,
      args: [nextDueAt, now, now, settings.userId, claimedDueAt],
    });
    if (claimed.rowsAffected !== 1) continue;

    settings.nextDueAt = nextDueAt;
    settings.lastAttemptAt = now;
    try {
      await deliverTelegramBackupForUser(env, db, settings.userId, settings, true);
    } catch (error) {
      console.error('Telegram backup delivery failed', {
        userId: settings.userId,
        error: safeTelegramError(error),
      });
    }
  }
}

async function deliverTelegramBackupForUser(
  env: Env,
  db: Client,
  userId: string,
  settings: TelegramBackupSettings,
  scheduled: boolean,
): Promise<{ fileName: string; sentAt: number }> {
  const attemptedAt = Date.now();
  if (!scheduled) {
    await db.execute({
      sql: 'UPDATE telegram_backup_settings SET last_attempt_at = ?, last_error = NULL, updated_at = ? WHERE user_id = ?',
      args: [attemptedAt, attemptedAt, userId],
    });
  }

  try {
    const token = await decryptTelegramBotToken(env.JWT_SECRET, settings.encryptedToken, settings.tokenIv);
    const { fileName, contents } = await buildTelegramBackupFile(db, userId);
    await sendTelegramBackupDocument(token, settings.chatId, fileName, contents);
    const sentAt = Date.now();
    await db.execute({
      sql: `UPDATE telegram_backup_settings
            SET last_sent_at = ?, last_attempt_at = ?, last_error = NULL, updated_at = ?
            WHERE user_id = ?`,
      args: [sentAt, attemptedAt, sentAt, userId],
    });
    return { fileName, sentAt };
  } catch (error) {
    const message = safeTelegramError(error);
    await db.execute({
      sql: `UPDATE telegram_backup_settings
            SET last_attempt_at = ?, last_error = ?, updated_at = ?
            WHERE user_id = ?`,
      args: [attemptedAt, message, Date.now(), userId],
    });
    if (error instanceof HttpError) throw error;
    throw new HttpError(502, message);
  }
}

async function buildTelegramBackupFile(db: Client, userId: string): Promise<{ fileName: string; contents: string }> {
  const database: Record<string, Array<Record<string, unknown>>> = {};
  for (const table of telegramBackupEntityTables) database[table] = [];
  let preferences: Record<string, unknown> = {};

  // sync_entities is the canonical current cloud state. Read it first.
  const entityRows = (await db.execute({
    sql: `SELECT entity_type, entity_id, payload_json
          FROM sync_entities
          WHERE user_id = ? AND deleted_at IS NULL
          ORDER BY entity_type, entity_id`,
    args: [userId],
  })).rows;
  applyTelegramBackupRows(entityRows, database, value => { preferences = value; });

  // Older/incomplete deployments can have a valid sync history while
  // sync_entities is unexpectedly empty (for example after an interrupted
  // legacy replace). Reconstruct the latest active state from sync_changes so
  // Telegram never silently emits an empty backup when recoverable cloud data
  // exists. The most recent __reset__ is respected.
  if (telegramBackupFinanceRecordCount(database) === 0) {
    const historyRows = (await db.execute({
      sql: `WITH last_reset AS (
              SELECT COALESCE(MAX(sequence), 0) AS reset_sequence
              FROM sync_changes
              WHERE user_id = ? AND entity_type = '__reset__'
            ),
            ranked AS (
              SELECT entity_type, entity_id, operation, payload_json, sequence,
                     ROW_NUMBER() OVER (
                       PARTITION BY entity_type, entity_id
                       ORDER BY sequence DESC
                     ) AS rn
              FROM sync_changes, last_reset
              WHERE user_id = ?
                AND sequence > last_reset.reset_sequence
                AND entity_type <> '__reset__'
            )
            SELECT entity_type, entity_id, payload_json
            FROM ranked
            WHERE rn = 1 AND operation = 'upsert'
            ORDER BY entity_type, entity_id`,
      args: [userId, userId],
    })).rows;
    applyTelegramBackupRows(historyRows, database, value => { preferences = value; });
  }

  const financeRecordCount = telegramBackupFinanceRecordCount(database);
  if (financeRecordCount === 0) {
    throw new HttpError(
      409,
      'The cloud copy contains no finance records, so an empty Telegram backup was not sent. Open Koinly on a device with your data, use Upload local changes once, then create the backup again.',
    );
  }

  const createdAt = new Date();
  const recordCounts = Object.fromEntries(
    telegramBackupEntityTables.map(table => [table, database[table].length]),
  );
  const payload = {
    version: 7,
    backup_type: 'telegram-cloud',
    created_at: createdAt.toISOString(),
    database,
    preferences,
    record_counts: recordCounts,
    finance_record_count: financeRecordCount,
  };
  const fileName = `koinly_telegram_${compactUtcTimestamp(createdAt)}.koinlybackup`;
  return { fileName, contents: encodeKoinlyBackup(payload) };
}

function applyTelegramBackupRows(
  rows: Array<Record<string, unknown>>,
  database: Record<string, Array<Record<string, unknown>>>,
  setPreferences: (value: Record<string, unknown>) => void,
): void {
  // Deduplicate by the same stable entity identity used by sync. This also
  // makes the history-recovery path safe if it is ever combined with canonical
  // rows in a future migration.
  const rowIndexes = new Map<string, Map<string, number>>();
  for (const table of telegramBackupEntityTables) rowIndexes.set(table, new Map());

  for (const row of rows) {
    const entityType = String(row.entity_type ?? '');
    const entityId = String(row.entity_id ?? '');
    if (!row.payload_json) continue;
    let payload: unknown;
    try {
      payload = JSON.parse(String(row.payload_json));
    } catch {
      continue;
    }
    if (entityType === 'preferences') {
      if (payload && typeof payload === 'object' && !Array.isArray(payload)) {
        setPreferences(payload as Record<string, unknown>);
      }
      continue;
    }
    if (!telegramBackupEntityTables.includes(entityType as typeof telegramBackupEntityTables[number])) continue;
    if (!payload || typeof payload !== 'object' || Array.isArray(payload)) continue;

    const target = database[entityType];
    const indexes = rowIndexes.get(entityType)!;
    const stableId = entityId || telegramBackupRowIdentity(entityType, payload as Record<string, unknown>);
    if (!stableId) {
      target.push(payload as Record<string, unknown>);
      continue;
    }
    const existingIndex = indexes.get(stableId);
    if (existingIndex == null) {
      indexes.set(stableId, target.length);
      target.push(payload as Record<string, unknown>);
    } else {
      target[existingIndex] = payload as Record<string, unknown>;
    }
  }
}

function telegramBackupRowIdentity(entityType: string, payload: Record<string, unknown>): string {
  if (entityType === 'budget_accounts') {
    return `${String(payload.budget_id ?? '')}\u0000${String(payload.account_id ?? '')}`;
  }
  if (entityType === 'budget_categories') {
    return `${String(payload.budget_id ?? '')}\u0000${String(payload.category_id ?? '')}`;
  }
  return String(payload.id ?? '');
}

function telegramBackupFinanceRecordCount(database: Record<string, Array<Record<string, unknown>>>): number {
  return telegramBackupEntityTables.reduce((total, table) => total + (database[table]?.length ?? 0), 0);
}

async function sendTelegramBackupDocument(token: string, chatId: string, fileName: string, contents: string): Promise<void> {
  if (contents.length > 45 * 1024 * 1024) {
    throw new HttpError(413, 'The generated Telegram backup is too large to upload safely. Download a local backup instead.');
  }
  for (let attempt = 1; attempt <= 3; attempt += 1) {
    try {
      const form = new FormData();
      form.set('chat_id', chatId);
      form.set('caption', `Koinly cloud backup\n${new Date().toISOString().replace('T', ' ').replace('.000Z', ' UTC')}`);
      form.set('document', new Blob([contents], { type: 'application/octet-stream' }), fileName);
      const response = await fetch(`https://api.telegram.org/bot${token}/sendDocument`, {
        method: 'POST',
        body: form,
      });
      if (response.ok) return;
      const text = await response.text();
      throw new Error(telegramApiFailure(response.status, text));
    } catch (error) {
      if (attempt >= 3) throw error;
      await delay(attempt * 1200);
    }
  }
}

async function telegramApiJson(token: string, method: string, body: Record<string, unknown>): Promise<Record<string, unknown>> {
  const response = await fetch(`https://api.telegram.org/bot${token}/${method}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body),
  });
  const text = await response.text();
  if (!response.ok) throw new HttpError(502, telegramApiFailure(response.status, text));
  try {
    return JSON.parse(text) as Record<string, unknown>;
  } catch {
    return { ok: true };
  }
}

function telegramApiFailure(status: number, body: string): string {
  try {
    const parsed = JSON.parse(body) as Record<string, unknown>;
    const description = cleanText(parsed.description, 180);
    if (description) return `Telegram rejected the request: ${description}`;
  } catch {}
  return `Telegram API returned HTTP ${status}.`;
}

async function readTelegramBackupSettings(db: Client, userId: string): Promise<TelegramBackupSettings> {
  const row = (await db.execute({
    sql: `SELECT user_id, enabled, bot_token_encrypted, bot_token_iv, chat_id, frequency,
                 hour, minute, weekday, month_day, timezone_offset_minutes, next_due_at,
                 last_sent_at, last_attempt_at, last_error
          FROM telegram_backup_settings WHERE user_id = ?`,
    args: [userId],
  })).rows[0];
  if (!row) {
    return {
      userId,
      enabled: false,
      tokenConfigured: false,
      encryptedToken: '',
      tokenIv: '',
      chatId: '',
      frequency: 'daily',
      hour: 2,
      minute: 0,
      weekday: 7,
      monthDay: 1,
      timezoneOffsetMinutes: 0,
      nextDueAt: null,
      lastSentAt: null,
      lastAttemptAt: null,
      lastError: null,
    };
  }
  return telegramBackupSettingsFromRow(row);
}

function telegramBackupSettingsFromRow(row: Record<string, unknown>): TelegramBackupSettings {
  return {
    userId: String(row.user_id ?? ''),
    enabled: Number(row.enabled ?? 0) === 1,
    tokenConfigured: Boolean(row.bot_token_encrypted),
    encryptedToken: String(row.bot_token_encrypted ?? ''),
    tokenIv: String(row.bot_token_iv ?? ''),
    chatId: String(row.chat_id ?? ''),
    frequency: normalizeTelegramBackupFrequency(row.frequency),
    hour: integerInRange(row.hour, 2, 0, 23, 'hour'),
    minute: integerInRange(row.minute, 0, 0, 59, 'minute'),
    weekday: integerInRange(row.weekday, 7, 1, 7, 'weekday'),
    monthDay: integerInRange(row.month_day, 1, 1, 31, 'monthDay'),
    timezoneOffsetMinutes: integerInRange(row.timezone_offset_minutes, 0, -840, 840, 'timezoneOffsetMinutes'),
    nextDueAt: nullableInteger(row.next_due_at),
    lastSentAt: nullableInteger(row.last_sent_at),
    lastAttemptAt: nullableInteger(row.last_attempt_at),
    lastError: row.last_error == null ? null : String(row.last_error),
  };
}

function publicTelegramBackupSettings(settings: TelegramBackupSettings): Record<string, unknown> {
  return {
    enabled: settings.enabled,
    tokenConfigured: settings.tokenConfigured,
    chatId: settings.chatId,
    frequency: settings.frequency,
    hour: settings.hour,
    minute: settings.minute,
    weekday: settings.weekday,
    monthDay: settings.monthDay,
    timezoneOffsetMinutes: settings.timezoneOffsetMinutes,
    nextDueAt: settings.nextDueAt,
    lastSentAt: settings.lastSentAt,
    lastError: settings.lastError,
  };
}

function normalizeTelegramBackupFrequency(value: unknown): TelegramBackupFrequency {
  const normalized = String(value ?? '').trim().toLowerCase();
  if (normalized === 'daily' || normalized === 'weekly' || normalized === 'monthly') return normalized;
  throw new HttpError(400, 'Backup frequency must be daily, weekly, or monthly.');
}

function normalizeTelegramChatId(value: unknown): string {
  const normalized = String(value ?? '').trim();
  if (!normalized) return '';
  if (/^-?\d{5,24}$/.test(normalized)) return normalized;
  if (/^@[A-Za-z0-9_]{5,32}$/.test(normalized)) return normalized;
  throw new HttpError(400, 'Telegram Chat ID must be a numeric group/channel ID or an @channel username.');
}

function validateTelegramBotToken(token: string): void {
  if (!/^\d{5,15}:[A-Za-z0-9_-]{20,}$/.test(token)) {
    throw new HttpError(400, 'Telegram bot token format is invalid.');
  }
}

function integerInRange(value: unknown, fallback: number, min: number, max: number, label: string): number {
  if (value == null || value === '') return fallback;
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < min || parsed > max) {
    throw new HttpError(400, `${label} must be between ${min} and ${max}.`);
  }
  return parsed;
}

function nullableInteger(value: unknown): number | null {
  if (value == null) return null;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? Math.trunc(parsed) : null;
}

export function nextTelegramBackupDueAt(
  settings: Pick<TelegramBackupSettings, 'frequency' | 'hour' | 'minute' | 'weekday' | 'monthDay' | 'timezoneOffsetMinutes'>,
  afterMs: number,
): number {
  const offsetMs = settings.timezoneOffsetMinutes * 60_000;
  const localNow = new Date(afterMs + offsetMs);
  const year = localNow.getUTCFullYear();
  const month = localNow.getUTCMonth();
  const day = localNow.getUTCDate();
  const toUtc = (y: number, m: number, d: number) => Date.UTC(y, m, d, settings.hour, settings.minute) - offsetMs;

  if (settings.frequency === 'daily') {
    let candidate = toUtc(year, month, day);
    if (candidate <= afterMs) candidate = toUtc(year, month, day + 1);
    return candidate;
  }

  if (settings.frequency === 'weekly') {
    const jsDay = localNow.getUTCDay();
    const currentWeekday = jsDay === 0 ? 7 : jsDay;
    let daysAhead = (settings.weekday - currentWeekday + 7) % 7;
    let candidate = toUtc(year, month, day + daysAhead);
    if (candidate <= afterMs) {
      daysAhead += 7;
      candidate = toUtc(year, month, day + daysAhead);
    }
    return candidate;
  }

  const monthlyCandidate = (candidateYear: number, candidateMonth: number): number => {
    const lastDay = new Date(Date.UTC(candidateYear, candidateMonth + 1, 0)).getUTCDate();
    return toUtc(candidateYear, candidateMonth, Math.min(settings.monthDay, lastDay));
  };
  let candidate = monthlyCandidate(year, month);
  if (candidate <= afterMs) {
    const nextMonthDate = new Date(Date.UTC(year, month + 1, 1));
    candidate = monthlyCandidate(nextMonthDate.getUTCFullYear(), nextMonthDate.getUTCMonth());
  }
  return candidate;
}

async function encryptTelegramBotToken(secret: string, plaintext: string): Promise<{ ciphertext: string; iv: string }> {
  const key = await telegramBackupEncryptionKey(secret, ['encrypt']);
  const iv = crypto.getRandomValues(new Uint8Array(new ArrayBuffer(12)));
  const encrypted = await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, key, enc.encode(plaintext));
  return { ciphertext: b64urlBytes(encrypted), iv: b64urlBytes(iv) };
}

async function decryptTelegramBotToken(secret: string, ciphertext: string, encodedIv: string): Promise<string> {
  try {
    const key = await telegramBackupEncryptionKey(secret, ['decrypt']);
    const decrypted = await crypto.subtle.decrypt(
      { name: 'AES-GCM', iv: bytesFromB64Url(encodedIv) },
      key,
      bytesFromB64Url(ciphertext),
    );
    return new TextDecoder().decode(decrypted);
  } catch {
    throw new HttpError(503, 'The saved Telegram bot token cannot be decrypted. Re-enter the token and save again.');
  }
}

async function telegramBackupEncryptionKey(secret: string, usages: KeyUsage[]): Promise<CryptoKey> {
  const material = await crypto.subtle.digest('SHA-256', enc.encode(`koinly-telegram-backup-token:${secret}`));
  return crypto.subtle.importKey('raw', material, { name: 'AES-GCM' }, false, usages);
}

function encodeKoinlyBackup(payload: unknown): string {
  const source = enc.encode(JSON.stringify(payload));
  const key = enc.encode(koinlyBackupCompatibilityKey);
  const encrypted = new Uint8Array(source.length);
  for (let index = 0; index < source.length; index += 1) {
    encrypted[index] = source[index] ^ key[index % key.length];
  }
  return bytesToBase64(encrypted);
}

function bytesToBase64(bytes: Uint8Array): string {
  const chunks: string[] = [];
  const chunkSize = 0x8000;
  for (let start = 0; start < bytes.length; start += chunkSize) {
    const chunk = bytes.subarray(start, Math.min(start + chunkSize, bytes.length));
    chunks.push(String.fromCharCode(...Array.from(chunk)));
  }
  return btoa(chunks.join(''));
}

function compactUtcTimestamp(value: Date): string {
  const pad = (input: number) => input.toString().padStart(2, '0');
  return `${value.getUTCFullYear()}${pad(value.getUTCMonth() + 1)}${pad(value.getUTCDate())}_${pad(value.getUTCHours())}${pad(value.getUTCMinutes())}${pad(value.getUTCSeconds())}`;
}

function safeTelegramError(error: unknown): string {
  const message = error instanceof Error ? error.message : String(error);
  return message
    .replace(/bot\d+:[A-Za-z0-9_-]+/g, 'bot[redacted]')
    .replace(/\d{5,15}:[A-Za-z0-9_-]{20,}/g, '[redacted bot token]')
    .replace(/\s+/g, ' ')
    .slice(0, 220);
}


function rootResponse(env: Env): Response {
  const mode = registrationMode(env);
  return json({
    ok: true,
    service: 'koinly-sync',
    configured: isWorkerConfigured(env),
    registrationMode: mode,
    endpoints: {
      health: '/health',
      register: 'POST /v1/auth/register',
      login: 'POST /v1/auth/login',
      refresh: 'POST /v1/auth/refresh',
      logout: 'POST /v1/auth/logout',
      initialSync: 'POST /v1/sync/initial',
      push: 'POST /v1/sync/push',
      replace: 'POST /v1/sync/replace',
      pull: 'GET /v1/sync/pull?cursor=0&limit=100',
      status: 'GET /v1/sync/status',
      ...(mode === 'first-user' ? { telegramBackup: '/v1/telegram-backup/*' } : {}),
      ...(mode === 'invite-key' ? { registrationKeyAdmin: 'Protected /v1/admin/registration-key/* endpoints' } : {}),
    },
  });
}

async function healthResponse(env: Env): Promise<Response> {
  const configured = isWorkerConfigured(env);
  if (!configured) {
    return json({
      ok: false,
      service: 'koinly-sync',
      configured: false,
      registrationMode: registrationMode(env),
      telegramBackupAvailable: registrationMode(env) === 'first-user',
      databaseReachable: false,
      schemaReady: false,
      missingTables: requiredTables,
    }, 503);
  }

  let db: Client | undefined;
  try {
    db = createClient({ url: env.TURSO_DATABASE_URL, authToken: env.TURSO_AUTH_TOKEN });
    const missingTables = await missingSchemaTables(db);
    const schemaReady = missingTables.length === 0;
    return json({
      ok: schemaReady,
      service: 'koinly-sync',
      configured: true,
      registrationMode: registrationMode(env),
      telegramBackupAvailable: registrationMode(env) === 'first-user',
      databaseReachable: true,
      schemaReady,
      missingTables,
    }, schemaReady ? 200 : 503);
  } catch (error) {
    return json({
      ok: false,
      service: 'koinly-sync',
      configured: true,
      registrationMode: registrationMode(env),
      telegramBackupAvailable: registrationMode(env) === 'first-user',
      databaseReachable: false,
      schemaReady: false,
      missingTables: requiredTables,
      error: databaseErrorMessage(error),
    }, 503);
  } finally {
    db?.close();
  }
}

function isWorkerConfigured(env: Env): boolean {
  return Boolean(
    env.TURSO_DATABASE_URL &&
    env.TURSO_AUTH_TOKEN &&
    env.JWT_SECRET?.length >= 32,
  );
}

export function registrationMode(env: Env): 'invite-key' | 'first-user' {
  return env.TELEGRAM_BOT_TOKEN && env.REGISTRATION_KEY_CHAT_ID && env.REGISTRATION_ADMIN_SECRET?.length >= 32
    ? 'invite-key'
    : 'first-user';
}

function validateWorkerConfig(env: Env): void {
  const missing = [
    ['TURSO_DATABASE_URL', env.TURSO_DATABASE_URL],
    ['TURSO_AUTH_TOKEN', env.TURSO_AUTH_TOKEN],
    ['JWT_SECRET', env.JWT_SECRET],
  ].filter(([, value]) => !value).map(([name]) => name);

  if (missing.length > 0) {
    throw new HttpError(503, `Worker is missing required secret(s): ${missing.join(', ')}.`);
  }
  if (env.JWT_SECRET.length < 32) {
    throw new HttpError(503, 'JWT_SECRET must contain at least 32 characters.');
  }
}

async function missingSchemaTables(db: Client): Promise<string[]> {
  const rows = (await db.execute({
    sql: `SELECT name FROM sqlite_master WHERE type = 'table' AND name IN (${requiredTables.map(() => '?').join(',')})`,
    args: requiredTables,
  })).rows;
  const existing = new Set(rows.map(row => String(row.name)));
  return requiredTables.filter(table => !existing.has(table));
}

function databaseErrorMessage(error: unknown): string {
  const message = error instanceof Error ? error.message : String(error);
  if (message.trim().length === 0) return 'Unknown database error.';
  return message.replace(/\s+/g, ' ').slice(0, 240);
}

async function register(request: Request, env: Env, db: Client, context: ExecutionContext): Promise<Response> {
  const body = await readJson(request);
  const email = normalizeEmail(body.email);
  const password = String(body.password ?? '');
  const inviteOnly = registrationMode(env) === 'invite-key';
  const registrationKey = inviteOnly ? normalizeRegistrationKey(body.registrationKey) : '';
  const deviceId = normalizeId(body.deviceId, 'deviceId');
  const deviceName = cleanText(body.deviceName, 80) || 'Koinly device';
  const platform = cleanText(body.platform, 40) || 'unknown';
  validatePassword(password);

  const now = Date.now();
  const userId = crypto.randomUUID();
  const passwordHash = await hashPassword(password, env.JWT_SECRET);
  const registrationKeyHash = inviteOnly ? await sha256(registrationKey) : '';
  const nextKey = inviteOnly ? await createRegistrationKeyRecord(env, 'SYSTEM_ROTATION', now, 'Used') : null;
  const transaction = await db.transaction('write');
  try {
    let keyRow: Record<string, unknown> | undefined;
    if (inviteOnly) {
      keyRow = (await transaction.execute({
        sql: `SELECT id, status, expires_at FROM registration_keys WHERE key_hash = ? LIMIT 1`,
        args: [registrationKeyHash],
      })).rows[0] as Record<string, unknown> | undefined;
      validateRegistrationKeyRow(keyRow, now);
    } else {
      const userCount = Number((await transaction.execute('SELECT COUNT(*) AS count FROM users')).rows[0]?.count ?? 0);
      if (userCount > 0) {
        throw new HttpError(403, 'Self-hosted registration is closed. Sign in with the first account.');
      }
    }

    await transaction.execute({
      sql: 'INSERT INTO users(id, email, password_hash, created_at, updated_at) VALUES (?, ?, ?, ?, ?)',
      args: [userId, email, passwordHash, now, now],
    });
    if (inviteOnly) {
      const consumed = await transaction.execute({
        sql: `UPDATE registration_keys
              SET status = 'USED', used_at = ?, used_by_user_id = ?
              WHERE id = ? AND status = 'ACTIVE' AND used_at IS NULL AND revoked_at IS NULL
                AND (expires_at IS NULL OR expires_at > ?)`,
        args: [now, userId, String(keyRow!.id), now],
      });
      if (consumed.rowsAffected !== 1) {
        throw new HttpError(409, 'Registration key has already been used.');
      }
    }
    await transaction.execute({
      sql: 'INSERT INTO devices(id, user_id, name, platform, created_at, last_seen_at) VALUES (?, ?, ?, ?, ?, ?)',
      args: [deviceId, userId, deviceName, platform, now, now],
    });
    if (nextKey) await insertRegistrationKey(transaction, nextKey);
    await transaction.commit();
  } catch (error) {
    if (error instanceof HttpError) throw error;
    const message = databaseErrorMessage(error);
    if (message.toLowerCase().includes('unique') || message.toLowerCase().includes('constraint')) {
      throw new HttpError(409, 'An account already exists for this email.');
    }
    throw new HttpError(503, `Could not create sync account: ${message}`);
  } finally {
    transaction.close();
  }
  if (nextKey) scheduleRegistrationKeyDelivery(env, context, nextKey);
  return issueTokens(env, db, { userId, email, deviceId });
}

type RegistrationKeyRecord = {
  id: string;
  plaintext: string;
  keyHash: string;
  encryptedKey: string;
  encryptionIv: string;
  createdAt: number;
  expiresAt: number;
  createdBy: string;
  previousStatus: string;
};

async function ensureActiveRegistrationKey(env: Env, db: Client, context: ExecutionContext): Promise<void> {
  const now = Date.now();
  const pending = await createRegistrationKeyRecord(env, 'SYSTEM_BOOTSTRAP', now, 'None');
  const transaction = await db.transaction('write');
  let created = false;
  try {
    await transaction.execute({
      sql: `UPDATE registration_keys SET status = 'EXPIRED'
            WHERE status = 'ACTIVE' AND expires_at IS NOT NULL AND expires_at <= ?`,
      args: [now],
    });
    const active = (await transaction.execute({
      sql: `SELECT id FROM registration_keys WHERE status = 'ACTIVE' LIMIT 1`,
      args: [],
    })).rows[0];
    if (!active) {
      await insertRegistrationKey(transaction, pending);
      created = true;
    }
    await transaction.commit();
  } catch (error) {
    const message = databaseErrorMessage(error).toLowerCase();
    if (!message.includes('unique') && !message.includes('constraint')) throw error;
  } finally {
    transaction.close();
  }
  if (created) scheduleRegistrationKeyDelivery(env, context, pending);
}

async function registrationKeyAdmin(request: Request, url: URL, env: Env, db: Client, context: ExecutionContext): Promise<Response> {
  if (registrationMode(env) !== 'invite-key') {
    throw new HttpError(404, 'Registration-key administration is not enabled.');
  }
  await requireRegistrationAdmin(request, env);
  await expireRegistrationKeys(db);

  if (request.method === 'POST' && url.pathname === '/v1/admin/registration-key/bootstrap') {
    await ensureActiveRegistrationKey(env, db, context);
    const row = await currentRegistrationKey(db);
    return privateJson({ ok: true, key: row ? registrationKeyMetadata(row) : null });
  }
  if (request.method === 'GET' && url.pathname === '/v1/admin/registration-key/status') {
    const row = await currentRegistrationKey(db);
    return privateJson({ ok: true, key: row ? registrationKeyMetadata(row) : null });
  }
  if (request.method === 'GET' && url.pathname === '/v1/admin/registration-key/reveal') {
    const row = await currentRegistrationKey(db);
    if (!row) throw new HttpError(404, 'No active registration key exists.');
    const key = await decryptRegistrationKey(env.JWT_SECRET, String(row.encrypted_key), String(row.encryption_iv));
    return privateJson({ ok: true, key, metadata: registrationKeyMetadata(row) });
  }
  if (request.method === 'POST' && url.pathname === '/v1/admin/registration-key/rotate') {
    const nextKey = await rotateRegistrationKey(env, db, 'ADMIN_ROTATION', 'Revoked');
    scheduleRegistrationKeyDelivery(env, context, nextKey);
    return privateJson({ ok: true, key: registrationKeyPublicMetadata(nextKey), delivery: 'PENDING' });
  }
  if (request.method === 'POST' && url.pathname === '/v1/admin/registration-key/revoke') {
    const now = Date.now();
    const result = await db.execute({
      sql: `UPDATE registration_keys SET status = 'REVOKED', revoked_at = ? WHERE status = 'ACTIVE'`,
      args: [now],
    });
    return privateJson({ ok: true, revoked: result.rowsAffected });
  }
  if (request.method === 'POST' && url.pathname === '/v1/admin/registration-key/retry-delivery') {
    const row = await currentRegistrationKey(db);
    if (!row) throw new HttpError(404, 'No active registration key exists.');
    const record = await registrationKeyRecordFromRow(env, row, 'Rotated');
    scheduleRegistrationKeyDelivery(env, context, record);
    return privateJson({ ok: true, delivery: 'PENDING', key: registrationKeyMetadata(row) });
  }
  return json({ error: 'Admin registration-key endpoint not found.' }, 404);
}

async function rotateRegistrationKey(env: Env, db: Client, createdBy: string, previousStatus: string): Promise<RegistrationKeyRecord> {
  const now = Date.now();
  const nextKey = await createRegistrationKeyRecord(env, createdBy, now, previousStatus);
  const transaction = await db.transaction('write');
  try {
    await transaction.execute({
      sql: `UPDATE registration_keys SET status = 'REVOKED', revoked_at = ? WHERE status = 'ACTIVE'`,
      args: [now],
    });
    await insertRegistrationKey(transaction, nextKey);
    await transaction.commit();
    return nextKey;
  } finally {
    transaction.close();
  }
}

async function expireRegistrationKeys(db: Client): Promise<void> {
  const now = Date.now();
  await db.execute({
    sql: `UPDATE registration_keys SET status = 'EXPIRED'
          WHERE status = 'ACTIVE' AND expires_at IS NOT NULL AND expires_at <= ?`,
    args: [now],
  });
}

async function currentRegistrationKey(db: Client): Promise<Record<string, unknown> | undefined> {
  const row = (await db.execute({
    sql: `SELECT id, encrypted_key, encryption_iv, created_at, expires_at, status, created_by,
                 delivery_status, delivery_attempts, last_delivery_attempt_at, delivered_at, delivery_error
          FROM registration_keys WHERE status = 'ACTIVE' ORDER BY created_at DESC LIMIT 1`,
    args: [],
  })).rows[0];
  return row as Record<string, unknown> | undefined;
}

async function createRegistrationKeyRecord(
  env: Env,
  createdBy: string,
  createdAt: number,
  previousStatus: string,
): Promise<RegistrationKeyRecord> {
  const plaintext = generateRegistrationKey();
  const normalized = normalizeRegistrationKey(plaintext);
  const encrypted = await encryptRegistrationKey(env.JWT_SECRET, plaintext);
  return {
    id: crypto.randomUUID(),
    plaintext,
    keyHash: await sha256(normalized),
    encryptedKey: encrypted.ciphertext,
    encryptionIv: encrypted.iv,
    createdAt,
    expiresAt: createdAt + numberEnv(env.REGISTRATION_KEY_TTL_SECONDS, 2592000) * 1000,
    createdBy,
    previousStatus,
  };
}

async function insertRegistrationKey(transaction: Transaction, key: RegistrationKeyRecord): Promise<void> {
  await transaction.execute({
    sql: `INSERT INTO registration_keys(
            id, key_hash, encrypted_key, encryption_iv, created_at, expires_at, status, created_by,
            delivery_status, delivery_attempts
          ) VALUES (?, ?, ?, ?, ?, ?, 'ACTIVE', ?, 'PENDING', 0)`,
    args: [key.id, key.keyHash, key.encryptedKey, key.encryptionIv, key.createdAt, key.expiresAt, key.createdBy],
  });
}

function validateRegistrationKeyRow(row: Record<string, unknown> | undefined, now: number): void {
  if (!row) throw new HttpError(403, 'Registration key is invalid.');
  const status = String(row.status ?? '');
  if (status === 'USED') throw new HttpError(409, 'Registration key has already been used.');
  if (status === 'REVOKED') throw new HttpError(403, 'Registration key has been revoked.');
  if (status === 'EXPIRED' || (row.expires_at != null && Number(row.expires_at) <= now)) {
    throw new HttpError(403, 'Registration key has expired.');
  }
  if (status !== 'ACTIVE') throw new HttpError(403, 'Registration key is not active.');
}

function generateRegistrationKey(): string {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  const payload = Array.from(bytes, byte => alphabet[byte & 31]).join('');
  return `KLY1-${payload.match(/.{1,4}/g)!.join('-')}`;
}

function normalizeRegistrationKey(value: unknown): string {
  const raw = String(value ?? '').trim();
  if (!raw) throw new HttpError(400, 'Registration key is required.');
  const normalized = raw.toUpperCase().replace(/[\s-]/g, '');
  if (!/^KLY1[A-HJ-NP-Z2-9]{32}$/.test(normalized)) {
    throw new HttpError(403, 'Registration key is invalid.');
  }
  return normalized;
}

async function encryptRegistrationKey(secret: string, plaintext: string): Promise<{ ciphertext: string; iv: string }> {
  const key = await registrationEncryptionKey(secret, ['encrypt']);
  const iv = crypto.getRandomValues(new Uint8Array(new ArrayBuffer(12)));
  const encrypted = await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, key, enc.encode(plaintext));
  return { ciphertext: b64urlBytes(encrypted), iv: b64urlBytes(iv) };
}

async function decryptRegistrationKey(secret: string, ciphertext: string, encodedIv: string): Promise<string> {
  try {
    const key = await registrationEncryptionKey(secret, ['decrypt']);
    const decrypted = await crypto.subtle.decrypt(
      { name: 'AES-GCM', iv: bytesFromB64Url(encodedIv) },
      key,
      bytesFromB64Url(ciphertext),
    );
    return new TextDecoder().decode(decrypted);
  } catch {
    throw new HttpError(503, 'The active registration key cannot be decrypted. Rotate it to create a replacement.');
  }
}

async function registrationEncryptionKey(secret: string, usages: KeyUsage[]): Promise<CryptoKey> {
  const material = await crypto.subtle.digest('SHA-256', enc.encode(`koinly-registration-key:${secret}`));
  return crypto.subtle.importKey('raw', material, { name: 'AES-GCM' }, false, usages);
}

async function requireRegistrationAdmin(request: Request, env: Env): Promise<void> {
  const header = request.headers.get('authorization') ?? '';
  const supplied = header.toLowerCase().startsWith('bearer ') ? header.slice(7) : '';
  if (!supplied || (await sha256(supplied)) !== (await sha256(env.REGISTRATION_ADMIN_SECRET))) {
    throw new HttpError(401, 'Invalid registration administrator credentials.');
  }
}

function scheduleRegistrationKeyDelivery(env: Env, context: ExecutionContext, key: RegistrationKeyRecord): void {
  context.waitUntil((async () => {
    const deliveryDb = createClient({ url: env.TURSO_DATABASE_URL, authToken: env.TURSO_AUTH_TOKEN });
    try {
      await deliverRegistrationKey(env, deliveryDb, key);
    } finally {
      deliveryDb.close();
    }
  })());
}

async function deliverRegistrationKey(env: Env, db: Client, key: RegistrationKeyRecord): Promise<void> {
  let failure = 'Telegram delivery failed.';
  for (let attempt = 1; attempt <= 3; attempt += 1) {
    const attemptedAt = Date.now();
    const pending = await db.execute({
      sql: `UPDATE registration_keys
            SET delivery_status = 'PENDING', delivery_attempts = delivery_attempts + 1,
                last_delivery_attempt_at = ?, delivery_error = NULL
            WHERE id = ? AND status = 'ACTIVE'`,
      args: [attemptedAt, key.id],
    });
    if (pending.rowsAffected !== 1) return;
    try {
      const response = await fetch(`https://api.telegram.org/bot${env.TELEGRAM_BOT_TOKEN}/sendMessage`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({
          chat_id: env.REGISTRATION_KEY_CHAT_ID,
          text: registrationKeyTelegramMessage(key),
          disable_web_page_preview: true,
        }),
      });
      if (!response.ok) throw new Error(`Telegram API returned HTTP ${response.status}.`);
      await db.execute({
        sql: `UPDATE registration_keys
              SET delivery_status = 'DELIVERED', delivered_at = ?, delivery_error = NULL
              WHERE id = ?`,
        args: [Date.now(), key.id],
      });
      return;
    } catch (error) {
      failure = safeDeliveryError(error);
      if (attempt < 3) await delay(attempt * 1000);
    }
  }
  await db.execute({
    sql: `UPDATE registration_keys SET delivery_status = 'FAILED', delivery_error = ? WHERE id = ?`,
    args: [failure, key.id],
  });
}

function registrationKeyTelegramMessage(key: RegistrationKeyRecord): string {
  const generated = new Date(key.createdAt).toISOString().replace('T', ' ').replace('.000Z', ' UTC');
  const expires = new Date(key.expiresAt).toISOString().replace('T', ' ').replace('.000Z', ' UTC');
  return `New Registration Key\n\nKey: ${key.plaintext}\n\nStatus: Active\nPrevious key: ${key.previousStatus}\nGenerated: ${generated}\nExpires: ${expires}`;
}

function safeDeliveryError(error: unknown): string {
  const message = error instanceof Error ? error.message : 'Telegram delivery failed.';
  return message.replace(/bot\d+:[A-Za-z0-9_-]+/g, 'bot[redacted]').replace(/\s+/g, ' ').slice(0, 180);
}

function delay(milliseconds: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, milliseconds));
}

async function registrationKeyRecordFromRow(env: Env, row: Record<string, unknown>, previousStatus: string): Promise<RegistrationKeyRecord> {
  return {
    id: String(row.id),
    plaintext: await decryptRegistrationKey(env.JWT_SECRET, String(row.encrypted_key), String(row.encryption_iv)),
    keyHash: '',
    encryptedKey: String(row.encrypted_key),
    encryptionIv: String(row.encryption_iv),
    createdAt: Number(row.created_at),
    expiresAt: Number(row.expires_at),
    createdBy: String(row.created_by),
    previousStatus,
  };
}

function registrationKeyPublicMetadata(key: RegistrationKeyRecord): Record<string, unknown> {
  return {
    id: key.id,
    status: 'ACTIVE',
    createdAt: key.createdAt,
    expiresAt: key.expiresAt,
    createdBy: key.createdBy,
  };
}

function registrationKeyMetadata(row: Record<string, unknown>): Record<string, unknown> {
  return {
    id: String(row.id),
    status: String(row.status),
    createdAt: Number(row.created_at),
    expiresAt: row.expires_at == null ? null : Number(row.expires_at),
    createdBy: String(row.created_by),
    deliveryStatus: String(row.delivery_status),
    deliveryAttempts: Number(row.delivery_attempts ?? 0),
    lastDeliveryAttemptAt: row.last_delivery_attempt_at == null ? null : Number(row.last_delivery_attempt_at),
    deliveredAt: row.delivered_at == null ? null : Number(row.delivered_at),
    deliveryError: row.delivery_error == null ? null : String(row.delivery_error),
  };
}

function privateJson(value: unknown, status = 200): Response {
  const response = json(value, status);
  response.headers.set('cache-control', 'no-store, private');
  return response;
}

async function login(request: Request, env: Env, db: Client): Promise<Response> {
  const body = await readJson(request);
  const email = normalizeEmail(body.email);
  const password = String(body.password ?? '');
  const deviceId = normalizeId(body.deviceId, 'deviceId');
  const deviceName = cleanText(body.deviceName, 80) || 'Koinly device';
  const platform = cleanText(body.platform, 40) || 'unknown';

  const row = (await db.execute({ sql: 'SELECT id, email, password_hash FROM users WHERE email = ?', args: [email] })).rows[0];
  if (!row || !(await verifyPassword(password, String(row.password_hash), env.JWT_SECRET))) {
    throw new HttpError(401, 'Invalid email or password.');
  }

  const now = Date.now();
  await db.execute({
    sql: `INSERT INTO devices(id, user_id, name, platform, created_at, last_seen_at)
          VALUES (?, ?, ?, ?, ?, ?)
          ON CONFLICT(user_id, id) DO UPDATE SET name = excluded.name, platform = excluded.platform, last_seen_at = excluded.last_seen_at, revoked_at = NULL`,
    args: [deviceId, String(row.id), deviceName, platform, now, now],
  });
  return issueTokens(env, db, { userId: String(row.id), email: String(row.email), deviceId });
}

async function refresh(request: Request, env: Env, db: Client): Promise<Response> {
  const body = await readJson(request);
  const refreshToken = String(body.refreshToken ?? '');
  const deviceId = normalizeId(body.deviceId, 'deviceId');
  if (!refreshToken) throw new HttpError(401, 'Missing refresh token.');

  const tokenHash = await sha256(refreshToken);
  const row = (await db.execute({
    sql: `SELECT rt.id, rt.user_id, u.email
          FROM refresh_tokens rt
          JOIN users u ON u.id = rt.user_id
          WHERE rt.token_hash = ? AND rt.device_id = ? AND rt.revoked_at IS NULL AND rt.expires_at > ?`,
    args: [tokenHash, deviceId, Date.now()],
  })).rows[0];
  if (!row) throw new HttpError(401, 'Refresh token is invalid or expired.');

  await db.execute({ sql: 'UPDATE refresh_tokens SET revoked_at = ?, rotated_at = ? WHERE id = ?', args: [Date.now(), Date.now(), String(row.id)] });
  return issueTokens(env, db, { userId: String(row.user_id), email: String(row.email), deviceId });
}

async function logout(request: Request, db: Client, auth: AuthContext): Promise<Response> {
  const body = await readJson(request);
  const refreshToken = String(body.refreshToken ?? '');
  if (refreshToken) {
    await db.execute({
      sql: 'UPDATE refresh_tokens SET revoked_at = ? WHERE user_id = ? AND token_hash = ?',
      args: [Date.now(), auth.userId, await sha256(refreshToken)],
    });
  }
  return json({ ok: true });
}

async function initialSync(request: Request, db: Client, auth: AuthContext): Promise<Response> {
  const body = await readJson(request);
  const adoptLocal = Boolean(body.adoptLocal);
  if (adoptLocal && Array.isArray(body.operations)) {
    return pushWithOperations(db, auth, body.operations, 1000);
  }
  return pull(new URL('https://koinly.local/v1/sync/pull?cursor=0&limit=250'), { MAX_SYNC_BATCH_SIZE: '250' } as Env, db, auth);
}

async function push(request: Request, env: Env, db: Client, auth: AuthContext): Promise<Response> {
  const body = await readJson(request);
  return pushWithOperations(db, auth, body.operations, numberEnv(env.MAX_SYNC_BATCH_SIZE, 100));
}

async function replaceAll(request: Request, env: Env, db: Client, auth: AuthContext): Promise<Response> {
  const body = await readJson(request);
  const rawOperations = body.operations;
  if (!Array.isArray(rawOperations)) throw new HttpError(400, 'operations must be an array.');
  const maxBatch = Math.max(numberEnv(env.MAX_SYNC_REPLACE_SIZE, 25000), 1000);
  if (rawOperations.length > maxBatch) throw new HttpError(413, `Replace limit is ${maxBatch} operations.`);

  const latestUpsertByEntity = new Map<string, SyncOperation>();
  for (const raw of rawOperations) {
    const op = validateOperation(raw);
    if (op.operation !== 'upsert') continue;
    latestUpsertByEntity.set(`${op.entityType}\u0000${op.entityId}`, op);
  }
  const operations = [...latestUpsertByEntity.values()];
  const now = Date.now();
  const resetOperationId = crypto.randomUUID();
  const accepted: Array<{ operationId: string; entityType: string; entityId: string; sequence: number; version: number }> = [];

  await db.batch([
    { sql: 'DELETE FROM sync_entities WHERE user_id = ?', args: [auth.userId] },
    {
      sql: `INSERT INTO sync_changes(user_id, entity_type, entity_id, operation, version, payload_json, device_id, operation_id, changed_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      args: [auth.userId, '__reset__', 'finance', 'delete', 0, null, auth.deviceId, resetOperationId, now],
    },
  ], 'write');

  const replaceChunkSize = 40;
  for (let start = 0; start < operations.length; start += replaceChunkSize) {
    const chunk = operations.slice(start, start + replaceChunkSize);
    const statements = [];
    for (const op of chunk) {
      const version = 1;
      const payloadJson = JSON.stringify(op.payload ?? {});
      statements.push(
        {
          sql: `INSERT INTO sync_entities(user_id, entity_type, entity_id, version, payload_json, deleted_at, updated_at, last_operation_id)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(user_id, entity_type, entity_id) DO UPDATE SET
                  version = excluded.version,
                  payload_json = excluded.payload_json,
                  deleted_at = excluded.deleted_at,
                  updated_at = excluded.updated_at,
                  last_operation_id = excluded.last_operation_id`,
          args: [auth.userId, op.entityType, op.entityId, version, payloadJson, null, now, op.operationId],
        },
        {
          sql: `INSERT INTO sync_changes(user_id, entity_type, entity_id, operation, version, payload_json, device_id, operation_id, changed_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
          args: [auth.userId, op.entityType, op.entityId, 'upsert', version, payloadJson, auth.deviceId, op.operationId, now],
        },
      );
      accepted.push({ operationId: op.operationId, entityType: op.entityType, entityId: op.entityId, sequence: 0, version });
    }
    await db.batch(statements, 'write');
  }

  const cursor = await maxSequence(db, auth);
  return json({ ok: true, mode: 'replace', cursor, accepted });
}

async function pushWithOperations(db: Client, auth: AuthContext, rawOperations: unknown, maxBatch: number): Promise<Response> {
  if (!Array.isArray(rawOperations)) throw new HttpError(400, 'operations must be an array.');
  if (rawOperations.length > maxBatch) throw new HttpError(413, `Batch limit is ${maxBatch} operations.`);

  const deduplicated = new Map<string, SyncOperation>();
  for (const raw of rawOperations) {
    const op = validateOperation(raw);
    if (!deduplicated.has(op.operationId)) deduplicated.set(op.operationId, op);
  }
  const operations = [...deduplicated.values()];
  if (operations.length === 0) return json({ ok: true, accepted: [], conflicts: [] });

  const accepted: Array<{ operationId: string; sequence: number; version: number }> = [];
  const conflicts: Array<{ operationId: string; entityType: string; entityId: string; serverVersion: number }> = [];
  const transaction = await db.transaction('write');

  try {
    // Resolve retries in one query. Joining back to sync_changes gives the exact
    // version assigned by the original successful write instead of echoing the
    // client's stale baseVersion.
    const processedPlaceholders = operations.map(() => '?').join(',');
    const processedRows = (await transaction.execute({
      sql: `SELECT p.operation_id, p.sequence,
                   COALESCE((
                     SELECT c.version FROM sync_changes c
                     WHERE c.user_id = p.user_id AND c.operation_id = p.operation_id
                     ORDER BY c.sequence DESC LIMIT 1
                   ), 0) AS version
            FROM processed_operations p
            WHERE p.user_id = ? AND p.operation_id IN (${processedPlaceholders})`,
      args: [auth.userId, ...operations.map(op => op.operationId)],
    })).rows;
    const processedById = new Map<string, { sequence: number; version: number }>(
      processedRows.map(row => [
        String(row.operation_id),
        { sequence: Number(row.sequence), version: Number(row.version) },
      ]),
    );

    const pending: SyncOperation[] = [];
    for (const op of operations) {
      const processed = processedById.get(op.operationId);
      if (processed) {
        accepted.push({ operationId: op.operationId, sequence: processed.sequence, version: processed.version });
      } else {
        pending.push(op);
      }
    }

    if (pending.length > 0) {
      const prepared = pending.map(op => {
        const baseVersion = op.baseVersion ?? 0;
        const version = baseVersion + 1;
        const now = Date.now();
        const payloadJson = op.operation === 'delete' ? null : JSON.stringify(op.payload ?? {});
        return { op, baseVersion, version, now, payloadJson };
      });

      // Every entity mutation is an atomic compare-and-set. New entities may
      // only be inserted from base version 0; existing entities update only when
      // the server version exactly matches the client's base version.
      const casResults = await transaction.batch(prepared.map(item => ({
        sql: `INSERT INTO sync_entities(user_id, entity_type, entity_id, version, payload_json, deleted_at, updated_at, last_operation_id)
              SELECT ?, ?, ?, ?, ?, ?, ?, ?
              WHERE ? = 0 OR EXISTS (
                SELECT 1 FROM sync_entities
                WHERE user_id = ? AND entity_type = ? AND entity_id = ? AND version = ?
              )
              ON CONFLICT(user_id, entity_type, entity_id) DO UPDATE SET
                version = excluded.version,
                payload_json = excluded.payload_json,
                deleted_at = excluded.deleted_at,
                updated_at = excluded.updated_at,
                last_operation_id = excluded.last_operation_id
              WHERE sync_entities.version = ?`,
        args: [
          auth.userId,
          item.op.entityType,
          item.op.entityId,
          item.version,
          item.payloadJson ?? '{}',
          item.op.operation === 'delete' ? item.now : null,
          item.now,
          item.op.operationId,
          item.baseVersion,
          auth.userId,
          item.op.entityType,
          item.op.entityId,
          item.baseVersion,
          item.baseVersion,
        ],
      })));

      const succeeded = prepared.filter((_, index) => casResults[index].rowsAffected === 1);
      const failed = prepared.filter((_, index) => casResults[index].rowsAffected !== 1);

      if (succeeded.length > 0) {
        // Append all accepted changes in one batch and use RETURNING so the
        // operation receipt stores the exact sequence without a follow-up SELECT.
        const changeResults = await transaction.batch(succeeded.map(item => ({
          sql: `INSERT INTO sync_changes(user_id, entity_type, entity_id, operation, version, payload_json, device_id, operation_id, changed_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                RETURNING sequence`,
          args: [
            auth.userId,
            item.op.entityType,
            item.op.entityId,
            item.op.operation,
            item.version,
            item.payloadJson,
            auth.deviceId,
            item.op.operationId,
            item.now,
          ],
        })));

        const receipts = succeeded.map((item, index) => {
          const result = changeResults[index];
          const sequence = Number(result.rows[0]?.sequence ?? result.lastInsertRowid ?? 0);
          if (!Number.isFinite(sequence) || sequence <= 0) {
            throw new HttpError(503, 'Could not determine the sync change sequence.');
          }
          return { item, sequence };
        });

        await transaction.batch(receipts.map(receipt => ({
          sql: 'INSERT INTO processed_operations(user_id, operation_id, sequence, created_at) VALUES (?, ?, ?, ?)',
          args: [auth.userId, receipt.item.op.operationId, receipt.sequence, receipt.item.now],
        })));

        for (const receipt of receipts) {
          accepted.push({
            operationId: receipt.item.op.operationId,
            sequence: receipt.sequence,
            version: receipt.item.version,
          });
        }
      }

      if (failed.length > 0) {
        const conditions = failed.map(() => '(entity_type = ? AND entity_id = ?)').join(' OR ');
        const versionRows = (await transaction.execute({
          sql: `SELECT entity_type, entity_id, version FROM sync_entities
                WHERE user_id = ? AND (${conditions})`,
          args: [auth.userId, ...failed.flatMap(item => [item.op.entityType, item.op.entityId])],
        })).rows;
        const versions = new Map<string, number>(
          versionRows.map(row => [
            `${String(row.entity_type)}\u0000${String(row.entity_id)}`,
            Number(row.version),
          ]),
        );
        for (const item of failed) {
          conflicts.push({
            operationId: item.op.operationId,
            entityType: item.op.entityType,
            entityId: item.op.entityId,
            serverVersion: versions.get(`${item.op.entityType}\u0000${item.op.entityId}`) ?? 0,
          });
        }
      }
    }

    await transaction.commit();
    return json({ ok: true, accepted, conflicts });
  } finally {
    transaction.close();
  }
}

async function pull(url: URL, env: Env, db: Client, auth: AuthContext): Promise<Response> {
  const cursor = Math.max(0, Number(url.searchParams.get('cursor') ?? '0') || 0);
  const limit = Math.min(Math.max(1, Number(url.searchParams.get('limit') ?? '100') || 100), numberEnv(env.MAX_SYNC_BATCH_SIZE, 100));
  const rows = (await db.execute({
    sql: `SELECT sequence, entity_type, entity_id, operation, version, payload_json, device_id, operation_id, changed_at
          FROM sync_changes
          WHERE user_id = ? AND sequence > ?
          ORDER BY sequence
          LIMIT ?`,
    args: [auth.userId, cursor, limit + 1],
  })).rows;
  const page = rows.slice(0, limit);
  const nextCursor = page.length ? Number(page[page.length - 1].sequence) : cursor;
  return json({
    cursor: nextCursor,
    hasMore: rows.length > limit,
    changes: page.map(row => ({
      sequence: Number(row.sequence),
      entityType: String(row.entity_type),
      entityId: String(row.entity_id),
      operation: String(row.operation),
      version: Number(row.version),
      payload: row.payload_json ? JSON.parse(String(row.payload_json)) : null,
      deviceId: String(row.device_id),
      operationId: String(row.operation_id),
      changedAt: Number(row.changed_at),
    })),
  });
}

async function status(db: Client, auth: AuthContext): Promise<Response> {
  await db.execute({ sql: 'UPDATE devices SET last_seen_at = ? WHERE user_id = ? AND id = ?', args: [Date.now(), auth.userId, auth.deviceId] });
  return json({ ok: true, serverCursor: await maxSequence(db, auth), userId: auth.userId, deviceId: auth.deviceId });
}

async function maxSequence(db: Client, auth: AuthContext): Promise<number> {
  const row = (await db.execute({ sql: 'SELECT COALESCE(MAX(sequence), 0) AS sequence FROM sync_changes WHERE user_id = ?', args: [auth.userId] })).rows[0];
  return Number(row?.sequence ?? 0);
}

async function issueTokens(env: Env, db: Client, auth: AuthContext): Promise<Response> {
  const now = Date.now();
  const accessExpiresAt = now + numberEnv(env.ACCESS_TOKEN_TTL_SECONDS, 900) * 1000;
  const refreshExpiresAt = now + numberEnv(env.REFRESH_TOKEN_TTL_SECONDS, 2592000) * 1000;
  const accessToken = await signToken(env.JWT_SECRET, { sub: auth.userId, email: auth.email, deviceId: auth.deviceId, exp: Math.floor(accessExpiresAt / 1000) });
  const refreshToken = crypto.randomUUID() + '.' + crypto.randomUUID();
  await db.execute({
    sql: 'INSERT INTO refresh_tokens(id, user_id, token_hash, device_id, expires_at, created_at) VALUES (?, ?, ?, ?, ?, ?)',
    args: [crypto.randomUUID(), auth.userId, await sha256(refreshToken), auth.deviceId, refreshExpiresAt, now],
  });
  return json({ accessToken, refreshToken, accessExpiresAt, refreshExpiresAt, user: { id: auth.userId, email: auth.email }, deviceId: auth.deviceId });
}

async function requireAuth(request: Request, env: Env): Promise<AuthContext> {
  const header = request.headers.get('authorization') ?? '';
  const token = header.toLowerCase().startsWith('bearer ') ? header.slice(7) : '';
  if (!token) throw new HttpError(401, 'Missing access token.');
  const payload = await verifyToken(env.JWT_SECRET, token);
  return { userId: String(payload.sub), email: String(payload.email), deviceId: String(payload.deviceId) };
}

async function signToken(secret: string, payload: Record<string, unknown>): Promise<string> {
  const header = b64url(JSON.stringify({ alg: 'HS256', typ: 'JWT' }));
  const body = b64url(JSON.stringify(payload));
  const key = await crypto.subtle.importKey('raw', enc.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const sig = await crypto.subtle.sign('HMAC', key, enc.encode(`${header}.${body}`));
  return `${header}.${body}.${b64urlBytes(sig)}`;
}

async function verifyToken(secret: string, token: string): Promise<Record<string, unknown>> {
  const parts = token.split('.');
  if (parts.length !== 3) throw new HttpError(401, 'Invalid access token.');
  const expected = await signDetached(secret, `${parts[0]}.${parts[1]}`);
  if (expected !== parts[2]) throw new HttpError(401, 'Invalid access token signature.');
  const payload = JSON.parse(atobUrl(parts[1])) as Record<string, unknown>;
  if (Number(payload.exp ?? 0) < Math.floor(Date.now() / 1000)) throw new HttpError(401, 'Access token expired.');
  return payload;
}

async function signDetached(secret: string, value: string): Promise<string> {
  const key = await crypto.subtle.importKey('raw', enc.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  return b64urlBytes(await crypto.subtle.sign('HMAC', key, enc.encode(value)));
}

async function hashPassword(password: string, pepper: string): Promise<string> {
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const saltRaw = b64urlBytes(salt);
  return `s256$${saltRaw}$${await sha256(`${saltRaw}.${pepper}.${password}`)}`;
}

async function verifyPassword(password: string, stored: string, pepper: string): Promise<boolean> {
  const [scheme, first, second, third] = stored.split('$');
  if (scheme === 's256') {
    return await sha256(`${first}.${pepper}.${password}`) === second;
  }
  if (scheme !== 'pbkdf2') return false;
  const iterationsRaw = first;
  const saltRaw = second;
  const hashRaw = third;
  if (!iterationsRaw || !saltRaw || !hashRaw) return false;
  const key = await crypto.subtle.importKey('raw', enc.encode(password), 'PBKDF2', false, ['deriveBits']);
  const salt = bytesFromB64Url(saltRaw);
  const bits = await crypto.subtle.deriveBits({ name: 'PBKDF2', hash: 'SHA-256', salt, iterations: Number(iterationsRaw) }, key, 256);
  return b64urlBytes(bits) === hashRaw;
}

async function sha256(value: string): Promise<string> {
  return b64urlBytes(await crypto.subtle.digest('SHA-256', enc.encode(value)));
}

function validateOperation(raw: unknown): SyncOperation {
  const value = raw as Record<string, unknown>;
  const operation = String(value.operation ?? '');
  if (operation !== 'upsert' && operation !== 'delete') throw new HttpError(400, 'Invalid operation.');
  return {
    operationId: normalizeId(value.operationId, 'operationId'),
    entityType: normalizeEntityType(value.entityType),
    entityId: normalizeId(value.entityId, 'entityId'),
    operation,
    payload: value.payload,
    baseVersion: Number(value.baseVersion ?? 0),
    clientUpdatedAt: Number(value.clientUpdatedAt ?? Date.now()),
  };
}

function normalizeEmail(value: unknown): string {
  const email = String(value ?? '').trim().toLowerCase();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) throw new HttpError(400, 'Enter a valid email address.');
  return email;
}

function validatePassword(password: string): void {
  if (password.length < 8) throw new HttpError(400, 'Password must be at least 8 characters.');
}

function normalizeEntityType(value: unknown): string {
  const entityType = String(value ?? '').trim();
  if (!/^[a-z_]{2,64}$/.test(entityType)) throw new HttpError(400, 'Invalid entity type.');
  return entityType;
}

function normalizeId(value: unknown, label: string): string {
  const id = String(value ?? '').trim();
  if (!/^[A-Za-z0-9._:-]{3,120}$/.test(id)) throw new HttpError(400, `Invalid ${label}.`);
  return id;
}

function cleanText(value: unknown, max: number): string {
  return String(value ?? '').trim().slice(0, max);
}

async function readJson(request: Request): Promise<Record<string, unknown>> {
  try {
    return await request.json() as Record<string, unknown>;
  } catch {
    throw new HttpError(400, 'Invalid JSON body.');
  }
}

function numberEnv(value: string | undefined, fallback: number): number {
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}

function b64url(value: string): string {
  return b64urlBytes(enc.encode(value));
}

function b64urlBytes(value: ArrayBuffer | Uint8Array): string {
  const bytes = value instanceof Uint8Array ? value : new Uint8Array(value);
  let raw = '';
  for (const byte of bytes) raw += String.fromCharCode(byte);
  return btoa(raw).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
}

function bytesFromB64Url(value: string): Uint8Array<ArrayBuffer> {
  const raw = atobUrl(value);
  const bytes = new Uint8Array(new ArrayBuffer(raw.length));
  for (let i = 0; i < raw.length; i += 1) {
    bytes[i] = raw.charCodeAt(i);
  }
  return bytes;
}

function atobUrl(value: string): string {
  const padded = value.replace(/-/g, '+').replace(/_/g, '/').padEnd(Math.ceil(value.length / 4) * 4, '=');
  return atob(padded);
}

function json(value: unknown, status = 200): Response {
  return cors(new Response(JSON.stringify(value), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8' },
  }));
}

function cors(response: Response): Response {
  response.headers.set('access-control-allow-origin', '*');
  response.headers.set('access-control-allow-methods', 'GET,POST,OPTIONS');
  response.headers.set('access-control-allow-headers', 'authorization,content-type');
  return response;
}

class HttpError extends Error {
  constructor(readonly status: number, message: string) {
    super(message);
  }
}
