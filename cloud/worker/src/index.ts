import { createClient, type Client } from '@libsql/client/web';
import { profilePage } from './profile.ts';

type Env = {
  TURSO_DATABASE_URL: string;
  TURSO_AUTH_TOKEN: string;
  JWT_SECRET: string;
  ADMIN_USERNAME?: string;
  ADMIN_PASSWORD_HASH?: string;
  ACCESS_TOKEN_TTL_SECONDS?: string;
  REFRESH_TOKEN_TTL_SECONDS?: string;
  MAX_SYNC_BATCH_SIZE?: string;
  MAX_SYNC_REPLACE_SIZE?: string;
  SYNC_HUB?: DurableObjectNamespace;
};

type AuthContext = {
  userId: string;
  username: string;
  deviceId: string;
  sessionVersion?: number;
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
  'telegram_backup_settings',
  'profile_media',
  'profile_media_chunks',
  'admin_sessions',
];

export class SyncHub {
  constructor(private readonly state: DurableObjectState) {}

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    if (request.method === 'GET' && url.pathname === '/live') {
      if ((request.headers.get('upgrade') ?? '').toLowerCase() !== 'websocket') {
        return new Response('Expected WebSocket upgrade.', { status: 426 });
      }
      const pair = new WebSocketPair();
      const [client, server] = Object.values(pair);
      this.state.acceptWebSocket(server);
      server.serializeAttachment({ deviceId: request.headers.get('x-koinly-device-id') ?? '' });
      return new Response(null, { status: 101, webSocket: client });
    }

    if (request.method === 'POST' && url.pathname === '/notify') {
      const payload = await request.json().catch(() => ({})) as Record<string, unknown>;
      const sourceDeviceId = String(payload.deviceId ?? '');
      const message = JSON.stringify({
        type: 'sync-change',
        deviceId: sourceDeviceId,
        changedAt: Number(payload.changedAt ?? Date.now()),
      });
      for (const socket of this.state.getWebSockets()) {
        const attachment = socket.deserializeAttachment() as { deviceId?: string } | null;
        if (sourceDeviceId && attachment?.deviceId === sourceDeviceId) continue;
        try { socket.send(message); } catch {}
      }
      return new Response(null, { status: 204 });
    }

    return new Response('Not found.', { status: 404 });
  }

  webSocketMessage(socket: WebSocket, message: string | ArrayBuffer): void {
    if (message === 'ping') {
      try { socket.send('pong'); } catch {}
    }
  }

  webSocketClose(socket: WebSocket, code: number, reason: string): void {
    try { socket.close(code, reason); } catch {}
  }

  webSocketError(socket: WebSocket): void {
    try { socket.close(1011, 'Realtime sync connection error.'); } catch {}
  }
}

export default {
  async fetch(request: Request, env: Env, context: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);
    let db: Client | undefined;

    try {
      // The browser portal has its own cookie authentication and never uses API CORS.
      if (url.pathname === '/profile' || url.pathname.startsWith('/profile/')) {
        return await profile(request, env);
      }
      if (request.method === 'OPTIONS') return cors(new Response(null, { status: 204 }));
      if (request.method === 'GET' && url.pathname === '/') return rootResponse(env);
      if (request.method === 'GET' && url.pathname === '/health') return healthResponse(env);

      validateWorkerConfig(env);
      db = createClient({ url: env.TURSO_DATABASE_URL, authToken: env.TURSO_AUTH_TOKEN });

      if (request.method === 'POST' && url.pathname === '/v1/auth/register') return await register(request, env, db);
      if (request.method === 'POST' && url.pathname === '/v1/auth/login') return await login(request, env, db);
      if (request.method === 'POST' && url.pathname === '/v1/auth/recover') return await recoverAccount(request, env, db);
      if (request.method === 'POST' && url.pathname === '/v1/auth/refresh') return await refresh(request, env, db);
      const auth = await requireAuth(request, env, db);
      if (request.method === 'POST' && url.pathname === '/v1/auth/logout') return await logout(request, db, auth);
      if (request.method === 'POST' && url.pathname === '/v1/auth/recovery-key') return await rotateRecoveryKey(env, db, auth);
      if (request.method === 'GET' && url.pathname === '/v1/sync/live') return await openLiveSync(request, env, auth);
      if (request.method === 'POST' && url.pathname === '/v1/sync/initial') {
        const response = await initialSync(request, db, auth);
        context.waitUntil(notifySyncHub(env, auth));
        return response;
      }
      if (request.method === 'POST' && url.pathname === '/v1/sync/push') {
        const response = await push(request, env, db, auth);
        context.waitUntil(notifySyncHub(env, auth));
        return response;
      }
      if (request.method === 'POST' && url.pathname === '/v1/sync/replace') {
        const response = await replaceAll(request, env, db, auth);
        context.waitUntil(notifySyncHub(env, auth));
        return response;
      }
      if (request.method === 'GET' && url.pathname === '/v1/sync/pull') return await pull(url, env, db, auth);
      if (request.method === 'GET' && url.pathname === '/v1/sync/status') return await status(db, auth);
      if (request.method === 'POST' && url.pathname === '/v1/profile-media/begin') return await beginProfileMediaUpload(request, db, auth);
      if (request.method === 'POST' && url.pathname === '/v1/profile-media/chunk') return await uploadProfileMediaChunk(request, db, auth);
      if (request.method === 'POST' && url.pathname === '/v1/profile-media/complete') {
        const response = await completeProfileMediaUpload(request, db, auth);
        context.waitUntil(notifySyncHub(env, auth));
        return response;
      }
      if (request.method === 'GET' && url.pathname === '/v1/profile-media/meta') return await profileMediaMetadata(db, auth);
      if (request.method === 'GET' && url.pathname === '/v1/profile-media/chunk') return await downloadProfileMediaChunk(url, db, auth);
      if (request.method === 'POST' && url.pathname === '/v1/profile-media/framing') {
        const response = await updateProfileMediaFraming(request, db, auth);
        context.waitUntil(notifySyncHub(env, auth));
        return response;
      }
      if (request.method === 'DELETE' && url.pathname === '/v1/profile-media') {
        const response = await deleteProfileMedia(db, auth);
        context.waitUntil(notifySyncHub(env, auth));
        return response;
      }
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
    // Every Koinly Worker is self-hosted, so scheduled Telegram backups are
    // available whenever the user enables them.
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

const adminCookie = '__Host-koinly-admin';
const adminSessionSeconds = 3600;

export async function profile(request: Request, env: Env, connect: () => Client = () => createClient({ url: env.TURSO_DATABASE_URL, authToken: env.TURSO_AUTH_TOKEN })): Promise<Response> {
  const url = new URL(request.url);
  const page = request.method === 'GET' && (url.pathname === '/profile' || url.pathname === '/profile/');
  const nonce = b64urlBytes(crypto.getRandomValues(new Uint8Array(18)));
  let db: Client | undefined;
  let response: Response;
  try {
    validateWorkerConfig(env);
    if (!env.ADMIN_USERNAME || normalizeUsername(env.ADMIN_USERNAME) !== env.ADMIN_USERNAME ||
        !/^pbkdf2\$100000\$[A-Za-z0-9_-]{22}\$[A-Za-z0-9_-]{43}$/.test(env.ADMIN_PASSWORD_HASH ?? '')) {
      throw new HttpError(503, 'Administrator login is not configured. Set ADMIN_USERNAME and ADMIN_PASSWORD in GitHub repository secrets, then run Deploy Self-Hosted Sync Worker.');
    }
    if (url.protocol !== 'https:' && !['localhost', '127.0.0.1', '[::1]'].includes(url.hostname)) {
      throw new HttpError(400, 'Administrator access requires HTTPS.');
    }
    if (!['GET', 'POST', 'DELETE'].includes(request.method)) throw new HttpError(405, 'Method not allowed.');
    if (request.method !== 'GET' && (request.headers.get('origin') !== url.origin || request.headers.get('x-profile-request') !== '1')) {
      throw new HttpError(403, 'This action must be submitted from the administration portal.');
    }
    db = connect();
    const token = (request.headers.get('cookie') ?? '').split(';').map(part => part.trim()).find(part => part.startsWith(adminCookie + '='))?.slice(adminCookie.length + 1) ?? '';
    // Binding the hash to all credentials invalidates sessions when any administrator secret changes.
    const sessionHash = await signDetached(env.JWT_SECRET, JSON.stringify(['profile', env.ADMIN_USERNAME, env.ADMIN_PASSWORD_HASH, token]));
    if (request.method === 'POST' && url.pathname === '/profile/api/login') {
      await enforceRateLimit(db, `admin-login:ip:${request.headers.get('cf-connecting-ip') ?? 'local'}`, 8, 900000);
      await enforceRateLimit(db, 'admin-login:global', 50, 900000);
      const body = await readProfileJson(request);
      const username = String(body.username ?? '').trim().toLowerCase();
      const password = typeof body.password === 'string' ? body.password : '';
      const validPassword = await verifyPassword(password, env.ADMIN_PASSWORD_HASH!);
      if (!constantTimeEqual(username, env.ADMIN_USERNAME) || !validPassword) throw new HttpError(401, 'Invalid administrator username or password.');
      const newToken = b64urlBytes(crypto.getRandomValues(new Uint8Array(32)));
      const newHash = await signDetached(env.JWT_SECRET, JSON.stringify(['profile', env.ADMIN_USERNAME, env.ADMIN_PASSWORD_HASH, newToken]));
      await db.batch([
        { sql: 'DELETE FROM admin_sessions WHERE expires_at <= ? OR token_hash = ?', args: [Date.now(), sessionHash] },
        { sql: 'INSERT INTO admin_sessions(token_hash, expires_at) VALUES (?, ?)', args: [newHash, Date.now() + adminSessionSeconds * 1000] },
      ], 'write');
      response = privateJson({ ok: true });
      response.headers.set('set-cookie', profileCookie(newToken, adminSessionSeconds));
    } else {
      const session = token && (await db.execute({ sql: 'SELECT token_hash FROM admin_sessions WHERE token_hash = ? AND expires_at > ?', args: [sessionHash, Date.now()] })).rows[0];
      if (page) {
        response = new Response(profilePage(Boolean(session), nonce), { headers: { 'content-type': 'text/html; charset=utf-8' } });
      } else if (request.method === 'POST' && url.pathname === '/profile/api/logout') {
        await db.execute({ sql: 'DELETE FROM admin_sessions WHERE token_hash = ?', args: [sessionHash] });
        response = privateJson({ ok: true });
        response.headers.set('set-cookie', profileCookie('', 0));
      } else {
        if (!session) throw new HttpError(401, 'Your administrator session expired. Sign in again.');
        response = await manageAccounts(request, url, env, db);
      }
    }
  } catch (error) {
    const status = error instanceof HttpError ? error.status : 503;
    const message = error instanceof HttpError ? error.message : 'Server/database error. Try again; if it persists, check the Worker configuration and apply the latest schema.';
    response = page
      ? new Response(profilePage(false, nonce, message), { status, headers: { 'content-type': 'text/html; charset=utf-8' } })
      : privateJson({ error: message }, status);
  } finally {
    db?.close();
  }
  response.headers.delete('access-control-allow-origin');
  response.headers.delete('access-control-allow-methods');
  response.headers.delete('access-control-allow-headers');
  response.headers.set('cache-control', 'no-store, private');
  response.headers.set('vary', 'Cookie');
  response.headers.set('content-security-policy', `default-src 'none'; script-src 'nonce-${nonce}'; style-src 'nonce-${nonce}'; connect-src 'self'; img-src 'self' data:; base-uri 'none'; form-action 'self'; frame-ancestors 'none'`);
  response.headers.set('x-content-type-options', 'nosniff');
  response.headers.set('x-frame-options', 'DENY');
  response.headers.set('referrer-policy', 'no-referrer');
  return response;
}

function profileCookie(token: string, maxAge: number): string {
  return `${adminCookie}=${token}; Path=/; HttpOnly; Secure; SameSite=Strict; Max-Age=${maxAge}`;
}

async function readProfileJson(request: Request): Promise<Record<string, unknown>> {
  if (request.headers.get('content-type')?.split(';')[0].trim() !== 'application/json') throw new HttpError(415, 'Expected a JSON request.');
  const reader = request.body?.getReader();
  if (!reader) throw new HttpError(400, 'Invalid JSON body.');
  const chunks: Uint8Array[] = [];
  let size = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.length;
    if (size > 8192) { await reader.cancel(); throw new HttpError(413, 'Request is too large.'); }
    chunks.push(value);
  }
  try {
    const bytes = new Uint8Array(size);
    let offset = 0;
    for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
    const body = JSON.parse(new TextDecoder().decode(bytes));
    if (!body || typeof body !== 'object' || Array.isArray(body)) throw new Error();
    return body as Record<string, unknown>;
  } catch { throw new HttpError(400, 'Invalid JSON body.'); }
}

async function manageAccounts(request: Request, url: URL, env: Env, db: Client): Promise<Response> {
  if (request.method === 'GET' && url.pathname === '/profile/api/accounts') {
    const page = Math.max(1, Number(url.searchParams.get('page') ?? 1));
    if (!Number.isSafeInteger(page) || page > 1000000) throw new HttpError(400, 'Invalid page.');
    const [count, accounts] = await db.batch([
      'SELECT COUNT(*) AS total FROM users',
      { sql: `SELECT id, username, created_at, updated_at,
                CASE WHEN EXISTS (SELECT 1 FROM devices WHERE user_id = users.id) THEN 'active' ELSE 'invited' END AS status
              FROM users ORDER BY created_at DESC, id LIMIT 50 OFFSET ?`, args: [(page - 1) * 50] },
    ], 'read');
    return privateJson({ total: Number(count.rows[0].total), page, pageSize: 50, accounts: accounts.rows.map(row => ({ id: String(row.id), username: String(row.username), createdAt: Number(row.created_at), updatedAt: Number(row.updated_at), status: String(row.status) })) });
  }
  if (request.method === 'POST' && url.pathname === '/profile/api/accounts') {
    const body = await readProfileJson(request);
    const username = normalizeUsername(body.username);
    const password = profilePassword(body.password);
    const now = Date.now();
    const result = await db.execute({
      sql: `INSERT INTO users(id, username, password_hash, created_at, updated_at) VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(username) DO NOTHING`,
      args: [crypto.randomUUID(), username, await hashPassword(password, env.JWT_SECRET), now, now],
    });
    if (!result.rowsAffected) throw new HttpError(409, 'Duplicate username. That username is already in use.');
    return privateJson({ ok: true, message: 'Account created.' }, 201);
  }
  const match = /^\/profile\/api\/accounts\/([A-Za-z0-9._:-]{3,120})(\/password)?$/.exec(url.pathname);
  if (!match) throw new HttpError(404, 'Not found.');
  const userId = match[1];
  if (request.method === 'POST' && match[2]) {
    const body = await readProfileJson(request);
    const hash = await hashPassword(profilePassword(body.password), env.JWT_SECRET);
    const now = Date.now();
    const [changed] = await db.batch([
      { sql: 'UPDATE users SET password_hash = ?, recovery_key_hash = NULL, session_version = session_version + 1, updated_at = ? WHERE id = ?', args: [hash, now, userId] },
      { sql: 'UPDATE refresh_tokens SET revoked_at = ? WHERE user_id = ? AND revoked_at IS NULL', args: [now, userId] },
      { sql: 'UPDATE devices SET revoked_at = ? WHERE user_id = ?', args: [now, userId] },
    ], 'write');
    if (!changed.rowsAffected) throw new HttpError(404, 'Account no longer exists.');
    return privateJson({ ok: true, message: 'Password changed. Existing sessions and recovery key revoked.' });
  }
  if (request.method === 'DELETE' && !match[2]) {
    // Delete children before their parent. The batch rolls back completely on any error.
    const results = await db.batch([
      ...['profile_media_chunks', 'profile_media', 'telegram_backup_settings', 'processed_operations', 'sync_changes', 'sync_entities', 'refresh_tokens', 'devices'].map(table => ({ sql: `DELETE FROM ${table} WHERE user_id = ?`, args: [userId] })),
      { sql: 'DELETE FROM users WHERE id = ?', args: [userId] },
    ], 'write');
    if (!results[results.length - 1].rowsAffected) throw new HttpError(404, 'Account no longer exists.');
    return privateJson({ ok: true, message: 'Account deleted.' });
  }
  throw new HttpError(405, 'Method not allowed.');
}

function profilePassword(value: unknown): string {
  if (typeof value !== 'string' || value.length > 256) throw new HttpError(400, 'Password must be 8-256 characters.');
  validatePassword(value);
  return value;
}

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
  'subscriptions',
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

async function telegramBackupSettings(env: Env, db: Client, auth: AuthContext): Promise<Response> {
  const settings = await readTelegramBackupSettings(db, auth.userId);
  return privateJson({ ok: true, settings: publicTelegramBackupSettings(settings) });
}

async function saveTelegramBackupSettings(request: Request, env: Env, db: Client, auth: AuthContext): Promise<Response> {
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
  return json({
    ok: true,
    service: 'koinly-sync',
    configured: isWorkerConfigured(env),
    registrationMode: 'first-user',
    endpoints: {
      profile: '/profile',
      health: '/health',
      register: 'POST /v1/auth/register',
      login: 'POST /v1/auth/login',
      recover: 'POST /v1/auth/recover',
      recoveryKey: 'POST /v1/auth/recovery-key',
      refresh: 'POST /v1/auth/refresh',
      logout: 'POST /v1/auth/logout',
      initialSync: 'POST /v1/sync/initial',
      push: 'POST /v1/sync/push',
      replace: 'POST /v1/sync/replace',
      pull: 'GET /v1/sync/pull?cursor=0&limit=100',
      status: 'GET /v1/sync/status',
      profileMedia: '/v1/profile-media/*',
      telegramBackup: '/v1/telegram-backup/*',
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
      registrationMode: 'first-user',
      telegramBackupAvailable: true,
      realtimeSyncAvailable: Boolean(env.SYNC_HUB),
      profileMediaSyncAvailable: true,
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
      registrationMode: 'first-user',
      telegramBackupAvailable: true,
      realtimeSyncAvailable: Boolean(env.SYNC_HUB),
      profileMediaSyncAvailable: true,
      databaseReachable: true,
      schemaReady,
      missingTables,
    }, schemaReady ? 200 : 503);
  } catch (error) {
    return json({
      ok: false,
      service: 'koinly-sync',
      configured: true,
      registrationMode: 'first-user',
      telegramBackupAvailable: true,
      realtimeSyncAvailable: Boolean(env.SYNC_HUB),
      profileMediaSyncAvailable: true,
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
  const missing = requiredTables.filter(table => !existing.has(table));
  if (!existing.has('users')) return missing;

  const userColumns = new Set((await db.execute("PRAGMA table_info('users')")).rows.map(row => String(row.name)));
  if (!userColumns.has('username')) missing.push('users.username');
  if (!userColumns.has('recovery_key_hash')) missing.push('users.recovery_key_hash');
  if (!userColumns.has('session_version')) missing.push('users.session_version');
  return missing;
}

function databaseErrorMessage(error: unknown): string {
  const message = error instanceof Error ? error.message : String(error);
  if (message.trim().length === 0) return 'Unknown database error.';
  return message.replace(/\s+/g, ' ').slice(0, 240);
}

export async function register(request: Request, env: Env, db: Client): Promise<Response> {
  if (env.ADMIN_USERNAME || env.ADMIN_PASSWORD_HASH) {
    throw new HttpError(403, 'Registration is managed by the Worker administrator at /profile.');
  }
  const body = await readJson(request);
  const username = normalizeUsername(body.username);
  const password = String(body.password ?? '');
  const deviceId = normalizeId(body.deviceId, 'deviceId');
  const deviceName = cleanText(body.deviceName, 80) || 'Koinly device';
  const platform = cleanText(body.platform, 40) || 'unknown';
  validatePassword(password);

  const now = Date.now();
  const userId = crypto.randomUUID();
  const passwordHash = await hashPassword(password, env.JWT_SECRET);
  const recoveryKey = generateRecoveryKey();
  const recoveryKeyHash = await hashRecoveryKey(recoveryKey, env.JWT_SECRET);
  const transaction = await db.transaction('write');
  try {
    const userCount = Number((await transaction.execute('SELECT COUNT(*) AS count FROM users')).rows[0]?.count ?? 0);
    if (userCount > 0) {
      throw new HttpError(403, 'Self-hosted registration is closed. Sign in with the first account.');
    }
    await transaction.execute({
      sql: 'INSERT INTO users(id, username, password_hash, recovery_key_hash, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
      args: [userId, username, passwordHash, recoveryKeyHash, now, now],
    });
    await transaction.execute({
      sql: 'INSERT INTO devices(id, user_id, name, platform, created_at, last_seen_at) VALUES (?, ?, ?, ?, ?, ?)',
      args: [deviceId, userId, deviceName, platform, now, now],
    });
    await transaction.commit();
  } catch (error) {
    if (error instanceof HttpError) throw error;
    const message = databaseErrorMessage(error);
    if (message.toLowerCase().includes('unique') || message.toLowerCase().includes('constraint')) {
      throw new HttpError(409, 'That username is already in use.');
    }
    throw new HttpError(503, `Could not create sync account: ${message}`);
  } finally {
    transaction.close();
  }
  return issueTokens(env, db, { userId, username, deviceId }, recoveryKey);
}


function delay(milliseconds: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, milliseconds));
}

function privateJson(value: unknown, status = 200): Response {
  const response = json(value, status);
  response.headers.set('cache-control', 'no-store, private');
  return response;
}

export async function login(request: Request, env: Env, db: Client): Promise<Response> {
  const body = await readJson(request);
  const username = normalizeUsername(body.username);
  const password = String(body.password ?? '');
  const deviceId = normalizeId(body.deviceId, 'deviceId');
  const deviceName = cleanText(body.deviceName, 80) || 'Koinly device';
  const platform = cleanText(body.platform, 40) || 'unknown';

  const row = (await db.execute({ sql: 'SELECT id, username, password_hash, session_version FROM users WHERE username = ?', args: [username] })).rows[0];
  if (!row || !(await verifyPassword(password, String(row.password_hash), env.JWT_SECRET))) {
    throw new HttpError(401, 'Invalid username or password.');
  }

  const now = Date.now();
  await db.execute({
    sql: `INSERT INTO devices(id, user_id, name, platform, created_at, last_seen_at)
          VALUES (?, ?, ?, ?, ?, ?)
          ON CONFLICT(user_id, id) DO UPDATE SET name = excluded.name, platform = excluded.platform, last_seen_at = excluded.last_seen_at, revoked_at = NULL`,
    args: [deviceId, String(row.id), deviceName, platform, now, now],
  });
  return issueTokens(env, db, { userId: String(row.id), username: String(row.username), deviceId, sessionVersion: Number(row.session_version) });
}

export async function recoverAccount(request: Request, env: Env, db: Client): Promise<Response> {
  const body = await readJson(request);
  const username = normalizeUsername(body.username);
  const recoveryKey = normalizeRecoveryKey(body.recoveryKey);
  const newPassword = String(body.newPassword ?? '');
  const deviceId = normalizeId(body.deviceId, 'deviceId');
  const deviceName = cleanText(body.deviceName, 80) || 'Koinly device';
  const platform = cleanText(body.platform, 40) || 'unknown';
  validatePassword(newPassword);

  await enforceRateLimit(db, `recover:${username}`, 8, 15 * 60 * 1000);
  const row = (await db.execute({
    sql: 'SELECT id, username, recovery_key_hash FROM users WHERE username = ?',
    args: [username],
  })).rows[0];
  const storedRecoveryHash = String(row?.recovery_key_hash ?? '');
  if (!row || !storedRecoveryHash || !constantTimeEqual(await hashRecoveryKey(recoveryKey, env.JWT_SECRET), storedRecoveryHash)) {
    throw new HttpError(401, 'Username or recovery key is incorrect.');
  }

  const now = Date.now();
  const passwordHash = await hashPassword(newPassword, env.JWT_SECRET);
  const transaction = await db.transaction('write');
  let sessionVersion = 0;
  try {
    const changed = await transaction.execute({
      sql: 'UPDATE users SET password_hash = ?, updated_at = ?, session_version = session_version + 1 WHERE id = ? AND recovery_key_hash = ? RETURNING session_version',
      args: [passwordHash, now, String(row.id), storedRecoveryHash],
    });
    if (!changed.rows[0]) throw new HttpError(401, 'Account or recovery key is no longer valid.');
    sessionVersion = Number(changed.rows[0].session_version);
    await transaction.execute({
      sql: 'UPDATE refresh_tokens SET revoked_at = ? WHERE user_id = ? AND revoked_at IS NULL',
      args: [now, String(row.id)],
    });
    await transaction.execute({
      sql: `INSERT INTO devices(id, user_id, name, platform, created_at, last_seen_at)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(user_id, id) DO UPDATE SET name = excluded.name, platform = excluded.platform, last_seen_at = excluded.last_seen_at, revoked_at = NULL`,
      args: [deviceId, String(row.id), deviceName, platform, now, now],
    });
    await transaction.commit();
  } finally {
    transaction.close();
  }
  return issueTokens(env, db, { userId: String(row.id), username: String(row.username), deviceId, sessionVersion });
}

export async function rotateRecoveryKey(env: Env, db: Client, auth: AuthContext): Promise<Response> {
  const recoveryKey = generateRecoveryKey();
  const recoveryKeyHash = await hashRecoveryKey(recoveryKey, env.JWT_SECRET);
  const changed = await db.execute({
    sql: 'UPDATE users SET recovery_key_hash = ?, updated_at = ? WHERE id = ? AND session_version = ?',
    args: [recoveryKeyHash, Date.now(), auth.userId, auth.sessionVersion ?? 0],
  });
  if (!changed.rowsAffected) throw new HttpError(401, 'Account session was revoked. Sign in again.');
  return privateJson({ ok: true, recoveryKey });
}

export async function refresh(request: Request, env: Env, db: Client): Promise<Response> {
  const body = await readJson(request);
  const refreshToken = String(body.refreshToken ?? '');
  const deviceId = normalizeId(body.deviceId, 'deviceId');
  if (!refreshToken) throw new HttpError(401, 'Missing refresh token.');

  const tokenHash = await sha256(refreshToken);
  const row = (await db.execute({
    sql: `SELECT rt.id, rt.user_id, u.username, u.session_version
          FROM refresh_tokens rt
          JOIN users u ON u.id = rt.user_id
          WHERE rt.token_hash = ? AND rt.device_id = ? AND rt.revoked_at IS NULL AND rt.expires_at > ?`,
    args: [tokenHash, deviceId, Date.now()],
  })).rows[0];
  if (!row) throw new HttpError(401, 'Refresh token is invalid or expired.');

  await db.execute({ sql: 'UPDATE refresh_tokens SET revoked_at = ?, rotated_at = ? WHERE id = ?', args: [Date.now(), Date.now(), String(row.id)] });
  return issueTokens(env, db, { userId: String(row.user_id), username: String(row.username), deviceId, sessionVersion: Number(row.session_version) });
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

async function openLiveSync(request: Request, env: Env, auth: AuthContext): Promise<Response> {
  if (!env.SYNC_HUB) throw new HttpError(503, 'Realtime sync is not configured on this Worker. Redeploy the latest Worker configuration.');
  if ((request.headers.get('upgrade') ?? '').toLowerCase() !== 'websocket') {
    throw new HttpError(426, 'Expected a WebSocket upgrade.');
  }
  const id = env.SYNC_HUB.idFromName(auth.userId);
  const headers = new Headers(request.headers);
  headers.set('x-koinly-device-id', auth.deviceId);
  return env.SYNC_HUB.get(id).fetch(new Request('https://sync-hub/live', {
    method: 'GET',
    headers,
  }));
}

async function notifySyncHub(env: Env, auth: AuthContext): Promise<void> {
  if (!env.SYNC_HUB) return;
  try {
    const id = env.SYNC_HUB.idFromName(auth.userId);
    await env.SYNC_HUB.get(id).fetch(new Request('https://sync-hub/notify', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ deviceId: auth.deviceId, changedAt: Date.now() }),
    }));
  } catch (error) {
    console.warn('Realtime sync notification failed', databaseErrorMessage(error));
  }
}


const profileMediaMaxBytes = 50 * 1024 * 1024;
const profileMediaMaxChunks = 128;
const profileMediaChunkBytes = 10 * 1024 * 1024;
const profileMediaMaxEncodedChunkLength = Math.ceil(profileMediaChunkBytes / 3) * 4;

function profileMediaVersion(value: unknown): string {
  return normalizeId(value, 'profile media version');
}

function profileMediaKind(value: unknown): 'photo' | 'gif' | 'video' {
  const kind = String(value ?? '').trim();
  if (kind !== 'photo' && kind !== 'gif' && kind !== 'video') {
    throw new HttpError(400, 'Invalid profile media type.');
  }
  return kind;
}

function profileMediaSize(value: unknown): number {
  const size = Number(value);
  if (!Number.isSafeInteger(size) || size <= 0 || size > profileMediaMaxBytes) {
    throw new HttpError(400, 'Profile media must be 50 MB or smaller.');
  }
  return size;
}

function profileMediaChunkCount(value: unknown): number {
  const count = Number(value);
  if (!Number.isSafeInteger(count) || count <= 0 || count > profileMediaMaxChunks) {
    throw new HttpError(400, 'Invalid profile media chunk count.');
  }
  return count;
}

function profileMediaScale(value: unknown, fallback = 1): number {
  const parsed = Number(value ?? fallback);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.min(3, Math.max(1, parsed));
}

function profileMediaAlignment(value: unknown): number {
  const parsed = Number(value ?? 0);
  if (!Number.isFinite(parsed)) return 0;
  return Math.min(1, Math.max(-1, parsed));
}

async function beginProfileMediaUpload(request: Request, db: Client, auth: AuthContext): Promise<Response> {
  const body = await readJson(request);
  const version = profileMediaVersion(body.version);
  profileMediaSize(body.sizeBytes);
  profileMediaChunkCount(body.chunkCount);
  const current = (await db.execute({
    sql: 'SELECT version FROM profile_media WHERE user_id = ?',
    args: [auth.userId],
  })).rows[0];
  const currentVersion = current ? String(current.version) : '';
  if (currentVersion) {
    await db.execute({
      sql: 'DELETE FROM profile_media_chunks WHERE user_id = ? AND version <> ?',
      args: [auth.userId, currentVersion],
    });
  } else {
    await db.execute({ sql: 'DELETE FROM profile_media_chunks WHERE user_id = ?', args: [auth.userId] });
  }
  if (version !== currentVersion) {
    await db.execute({
      sql: 'DELETE FROM profile_media_chunks WHERE user_id = ? AND version = ?',
      args: [auth.userId, version],
    });
  }
  return json({ ok: true, version });
}

async function uploadProfileMediaChunk(request: Request, db: Client, auth: AuthContext): Promise<Response> {
  const body = await readJson(request);
  const version = profileMediaVersion(body.version);
  const index = Number(body.index);
  if (!Number.isSafeInteger(index) || index < 0 || index >= profileMediaMaxChunks) {
    throw new HttpError(400, 'Invalid profile media chunk index.');
  }
  const data = typeof body.data === 'string' ? body.data : '';
  if (!data || data.length > profileMediaMaxEncodedChunkLength || !/^[A-Za-z0-9+/]+={0,2}$/.test(data)) {
    throw new HttpError(400, 'Invalid profile media chunk.');
  }
  await db.execute({
    sql: `INSERT INTO profile_media_chunks(user_id, version, chunk_index, data_base64)
          VALUES (?, ?, ?, ?)
          ON CONFLICT(user_id, version, chunk_index) DO UPDATE SET data_base64 = excluded.data_base64`,
    args: [auth.userId, version, index, data],
  });
  return json({ ok: true, index });
}

async function completeProfileMediaUpload(request: Request, db: Client, auth: AuthContext): Promise<Response> {
  const body = await readJson(request);
  const version = profileMediaVersion(body.version);
  const originalName = cleanText(body.originalName, 240);
  if (!originalName) throw new HttpError(400, 'Profile media file name is required.');
  const kind = profileMediaKind(body.kind);
  const sizeBytes = profileMediaSize(body.sizeBytes);
  const chunkCount = profileMediaChunkCount(body.chunkCount);
  const scale = profileMediaScale(body.scale);
  const alignmentX = profileMediaAlignment(body.alignmentX);
  const alignmentY = profileMediaAlignment(body.alignmentY);
  const uploaded = (await db.execute({
    sql: 'SELECT COUNT(*) AS count FROM profile_media_chunks WHERE user_id = ? AND version = ?',
    args: [auth.userId, version],
  })).rows[0];
  if (Number(uploaded?.count ?? 0) !== chunkCount) {
    throw new HttpError(409, 'Profile media upload is incomplete. Retry the upload.');
  }
  const now = Date.now();
  await db.batch([
    {
      sql: `INSERT INTO profile_media(user_id, version, original_name, media_kind, size_bytes, chunk_count, scale, alignment_x, alignment_y, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(user_id) DO UPDATE SET
              version = excluded.version,
              original_name = excluded.original_name,
              media_kind = excluded.media_kind,
              size_bytes = excluded.size_bytes,
              chunk_count = excluded.chunk_count,
              scale = excluded.scale,
              alignment_x = excluded.alignment_x,
              alignment_y = excluded.alignment_y,
              updated_at = excluded.updated_at`,
      args: [auth.userId, version, originalName, kind, sizeBytes, chunkCount, scale, alignmentX, alignmentY, now],
    },
    {
      sql: 'DELETE FROM profile_media_chunks WHERE user_id = ? AND version <> ?',
      args: [auth.userId, version],
    },
  ], 'write');
  return json({ ok: true, version, updatedAt: now });
}

async function profileMediaMetadata(db: Client, auth: AuthContext): Promise<Response> {
  const row = (await db.execute({
    sql: `SELECT version, original_name, media_kind, size_bytes, chunk_count, scale, alignment_x, alignment_y, updated_at
          FROM profile_media WHERE user_id = ?`,
    args: [auth.userId],
  })).rows[0];
  if (!row) return privateJson({ media: null });
  return privateJson({
    media: {
      version: String(row.version),
      originalName: String(row.original_name),
      kind: String(row.media_kind),
      sizeBytes: Number(row.size_bytes),
      chunkCount: Number(row.chunk_count),
      scale: Number(row.scale),
      alignmentX: Number(row.alignment_x),
      alignmentY: Number(row.alignment_y),
      updatedAt: Number(row.updated_at),
    },
  });
}

async function downloadProfileMediaChunk(url: URL, db: Client, auth: AuthContext): Promise<Response> {
  const version = profileMediaVersion(url.searchParams.get('version'));
  const index = Number(url.searchParams.get('index') ?? '-1');
  if (!Number.isSafeInteger(index) || index < 0 || index >= profileMediaMaxChunks) {
    throw new HttpError(400, 'Invalid profile media chunk index.');
  }
  const row = (await db.execute({
    sql: `SELECT c.data_base64
          FROM profile_media_chunks c
          JOIN profile_media m ON m.user_id = c.user_id AND m.version = c.version
          WHERE c.user_id = ? AND c.version = ? AND c.chunk_index = ?`,
    args: [auth.userId, version, index],
  })).rows[0];
  if (!row) throw new HttpError(404, 'Profile media chunk was not found.');
  return privateJson({ data: String(row.data_base64), index });
}

async function updateProfileMediaFraming(request: Request, db: Client, auth: AuthContext): Promise<Response> {
  const body = await readJson(request);
  const version = profileMediaVersion(body.version);
  const scale = profileMediaScale(body.scale);
  const alignmentX = profileMediaAlignment(body.alignmentX);
  const alignmentY = profileMediaAlignment(body.alignmentY);
  const now = Date.now();
  const result = await db.execute({
    sql: `UPDATE profile_media
          SET scale = ?, alignment_x = ?, alignment_y = ?, updated_at = ?
          WHERE user_id = ? AND version = ?`,
    args: [scale, alignmentX, alignmentY, now, auth.userId, version],
  });
  if (!result.rowsAffected) throw new HttpError(409, 'Profile media changed on another device. Sync and try again.');
  return json({ ok: true, version, updatedAt: now });
}

async function deleteProfileMedia(db: Client, auth: AuthContext): Promise<Response> {
  await db.batch([
    { sql: 'DELETE FROM profile_media_chunks WHERE user_id = ?', args: [auth.userId] },
    { sql: 'DELETE FROM profile_media WHERE user_id = ?', args: [auth.userId] },
  ], 'write');
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

async function issueTokens(env: Env, db: Client, auth: AuthContext, recoveryKey?: string): Promise<Response> {
  const now = Date.now();
  const accessExpiresAt = now + numberEnv(env.ACCESS_TOKEN_TTL_SECONDS, 900) * 1000;
  const refreshExpiresAt = now + numberEnv(env.REFRESH_TOKEN_TTL_SECONDS, 2592000) * 1000;
  const accessToken = await signToken(env.JWT_SECRET, { sub: auth.userId, username: auth.username, deviceId: auth.deviceId, ver: auth.sessionVersion ?? 0, exp: Math.floor(accessExpiresAt / 1000) });
  const refreshToken = crypto.randomUUID() + '.' + crypto.randomUUID();
  const inserted = await db.execute({
    sql: `INSERT INTO refresh_tokens(id, user_id, token_hash, device_id, expires_at, created_at)
          SELECT ?, ?, ?, ?, ?, ? FROM users WHERE id = ? AND session_version = ?`,
    args: [crypto.randomUUID(), auth.userId, await sha256(refreshToken), auth.deviceId, refreshExpiresAt, now, auth.userId, auth.sessionVersion ?? 0],
  });
  if (!inserted.rowsAffected) throw new HttpError(401, 'Account session was revoked. Sign in again.');
  return privateJson({
    accessToken,
    refreshToken,
    accessExpiresAt,
    refreshExpiresAt,
    user: { id: auth.userId, username: auth.username },
    deviceId: auth.deviceId,
    ...(recoveryKey ? { recoveryKey } : {}),
  });
}

export async function requireAuth(request: Request, env: Env, db: Client): Promise<AuthContext> {
  const header = request.headers.get('authorization') ?? '';
  const token = header.toLowerCase().startsWith('bearer ') ? header.slice(7) : '';
  if (!token) throw new HttpError(401, 'Missing access token.');
  const payload = await verifyToken(env.JWT_SECRET, token);
  const row = (await db.execute({ sql: 'SELECT session_version FROM users WHERE id = ?', args: [String(payload.sub)] })).rows[0];
  if (!row || Number(payload.ver ?? 0) !== Number(row.session_version)) {
    throw new HttpError(401, 'Account session was revoked. Sign in again.');
  }
  const username = String(payload.username ?? payload.email ?? '');
  return { userId: String(payload.sub), username, deviceId: String(payload.deviceId), sessionVersion: Number(row.session_version) };
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
  if (!constantTimeEqual(expected, parts[2])) throw new HttpError(401, 'Invalid access token signature.');
  let payload: Record<string, unknown>;
  try { payload = JSON.parse(atobUrl(parts[1])); } catch { throw new HttpError(401, 'Invalid access token.'); }
  if (!payload || typeof payload.exp !== 'number' || !Number.isFinite(payload.exp) || payload.exp <= Math.floor(Date.now() / 1000)) throw new HttpError(401, 'Access token expired.');
  return payload;
}

async function signDetached(secret: string, value: string): Promise<string> {
  const key = await crypto.subtle.importKey('raw', enc.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  return b64urlBytes(await crypto.subtle.sign('HMAC', key, enc.encode(value)));
}

export async function hashPassword(password: string, _pepper = ''): Promise<string> {
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const key = await crypto.subtle.importKey('raw', enc.encode(password), 'PBKDF2', false, ['deriveBits']);
  // ponytail: Workers caps Web Crypto PBKDF2 at 100,000 iterations; use a memory-hard KDF when the runtime supports it natively.
  const bits = await crypto.subtle.deriveBits({ name: 'PBKDF2', hash: 'SHA-256', salt, iterations: 100000 }, key, 256);
  return `pbkdf2$100000$${b64urlBytes(salt)}$${b64urlBytes(bits)}`;
}

export async function verifyPassword(password: string, stored: string, pepper = ''): Promise<boolean> {
  const [scheme, first, second, third] = stored.split('$');
  if (scheme === 's256') {
    return constantTimeEqual(await sha256(`${first}.${pepper}.${password}`), second ?? '');
  }
  if (scheme !== 'pbkdf2') return false;
  const iterationsRaw = first;
  const saltRaw = second;
  const hashRaw = third;
  if (!iterationsRaw || !saltRaw || !hashRaw) return false;
  const key = await crypto.subtle.importKey('raw', enc.encode(password), 'PBKDF2', false, ['deriveBits']);
  const salt = bytesFromB64Url(saltRaw);
  const bits = await crypto.subtle.deriveBits({ name: 'PBKDF2', hash: 'SHA-256', salt, iterations: Number(iterationsRaw) }, key, 256);
  return constantTimeEqual(b64urlBytes(bits), hashRaw);
}

function generateRecoveryKey(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(20));
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  let body = '';
  for (const byte of bytes) body += alphabet[byte % alphabet.length];
  return `KLY-${body.slice(0, 5)}-${body.slice(5, 10)}-${body.slice(10, 15)}-${body.slice(15, 20)}`;
}

async function hashRecoveryKey(recoveryKey: string, secret: string): Promise<string> {
  return sha256(`recovery.${secret}.${recoveryKey}`);
}

function constantTimeEqual(left: string, right: string): boolean {
  if (left.length !== right.length) return false;
  let diff = 0;
  for (let i = 0; i < left.length; i += 1) diff |= left.charCodeAt(i) ^ right.charCodeAt(i);
  return diff === 0;
}

async function enforceRateLimit(db: Client, key: string, maxAttempts: number, windowMs: number): Promise<void> {
  const now = Date.now();
  const row = (await db.execute({
    sql: `INSERT INTO rate_limits(key, window_start, count) VALUES (?, ?, 1)
          ON CONFLICT(key) DO UPDATE SET
            count = CASE WHEN window_start <= ? THEN 1 ELSE count + 1 END,
            window_start = CASE WHEN window_start <= ? THEN excluded.window_start ELSE window_start END
          RETURNING count`,
    args: [key, now, now - windowMs, now - windowMs],
  })).rows[0];
  if (Number(row.count) > maxAttempts) throw new HttpError(429, 'Too many attempts. Try again in 15 minutes.');
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

function normalizeUsername(value: unknown): string {
  const username = String(value ?? '').trim().toLowerCase();
  if (!/^[a-z0-9][a-z0-9._-]{1,30}[a-z0-9]$/.test(username)) {
    throw new HttpError(400, 'Username must be 3-32 characters using letters, numbers, dots, dashes, or underscores.');
  }
  return username;
}

function normalizeRecoveryKey(value: unknown): string {
  const recoveryKey = String(value ?? '').trim().toUpperCase().replace(/\s+/g, '');
  if (!/^KLY-[A-Z0-9-]{23,80}$/.test(recoveryKey)) throw new HttpError(400, 'Enter a valid recovery key.');
  return recoveryKey;
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
  response.headers.set('access-control-allow-methods', 'GET,POST,DELETE,OPTIONS');
  response.headers.set('access-control-allow-headers', 'authorization,content-type');
  return response;
}

class HttpError extends Error {
  constructor(readonly status: number, message: string) {
    super(message);
  }
}
