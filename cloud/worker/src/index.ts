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
  KOINLY_WORKER_VERSION?: string;
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
  'google_drive_backup_settings',
  'analytics_upload_settings',
  'analytics_pdf_schedules',
  'profile_media',
  'profile_media_chunks',
  'admin_sessions',
  'worker_state',
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
      if (request.method === 'GET' && url.pathname === '/v1/analytics-upload/google-drive/callback') {
        return await googleDriveAnalyticsCallback(request, env, db);
      }
      const auth = await requireAuth(request, env, db);
      if (request.method === 'POST' && url.pathname === '/v1/auth/logout') return await logout(request, db, auth);
      if (request.method === 'POST' && url.pathname === '/v1/auth/recovery-key') return await rotateRecoveryKey(env, db, auth);
      if (request.method === 'GET' && url.pathname === '/v1/deployment-recovery/profile') return await deploymentRecoveryProfile(db, env, auth);
      if (request.method === 'POST' && url.pathname === '/v1/deployment-recovery/profile') return await saveDeploymentRecoveryProfile(request, db, env, auth);
      if (request.method === 'DELETE' && url.pathname === '/v1/deployment-recovery/profile') return await deleteDeploymentRecoveryProfile(db, auth);
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
      if (request.method === 'GET' && url.pathname === '/v1/google-drive-backup/settings') return await googleDriveBackupSettings(db, auth);
      if (request.method === 'POST' && url.pathname === '/v1/google-drive-backup/settings') return await saveGoogleDriveBackupSettings(request, db, auth);
      if (request.method === 'POST' && url.pathname === '/v1/google-drive-backup/send-now') return await sendGoogleDriveBackupNow(env, db, auth);
      if (request.method === 'GET' && url.pathname === '/v1/analytics-upload/google-drive/settings') return await googleDriveAnalyticsSettings(db, auth);
      if (request.method === 'POST' && url.pathname === '/v1/analytics-upload/google-drive/settings') return await saveGoogleDriveAnalyticsSettings(request, env, db, auth);
      if (request.method === 'POST' && url.pathname === '/v1/analytics-upload/google-drive/connect-url') return await googleDriveAnalyticsConnectUrl(request, env, db, auth);
      if (request.method === 'DELETE' && url.pathname === '/v1/analytics-upload/google-drive/connection') return await disconnectGoogleDriveAnalytics(env, db, auth);
      if (request.method === 'POST' && url.pathname === '/v1/analytics-upload/telegram') return await uploadAnalyticsPdfToTelegram(request, env, db, auth);
      if (request.method === 'POST' && url.pathname === '/v1/analytics-upload/google-drive') return await uploadAnalyticsPdfToGoogleDrive(request, env, db, auth);
      if (request.method === 'GET' && url.pathname === '/v1/analytics-upload/schedules') return await analyticsPdfSchedules(db, auth);
      if (request.method === 'POST' && url.pathname.startsWith('/v1/analytics-upload/schedules/')) return await saveAnalyticsPdfSchedule(request, env, db, auth, url.pathname);

      return json({ error: 'Not found.' }, 404);
    } catch (error) {
      const statusCode = error instanceof HttpError ? error.status : 500;
      const message = error instanceof HttpError ? error.message : 'Internal server error.';
      const code = error instanceof HttpError ? error.code : undefined;
      if (!(error instanceof HttpError)) {
        console.error('Unhandled sync worker error', {
          path: url.pathname,
          method: request.method,
          error: databaseErrorMessage(error),
        });
      }
      return json({ error: message, ...(code ? { code } : {}) }, statusCode);
    } finally {
      db?.close();
    }
  },

  async scheduled(_controller: ScheduledController, env: Env, _context: ExecutionContext): Promise<void> {
    // A single five-minute cron checks all user-configured uploads. Schedule
    // validation keeps Telegram report, Drive report, Telegram backup, and
    // Google Drive backup jobs at least five minutes apart so they do not pile external requests into the
    // same Cloudflare invocation.
    validateWorkerConfig(env);
    const db = createClient({ url: env.TURSO_DATABASE_URL, authToken: env.TURSO_AUTH_TOKEN });
    try {
      await runDueTelegramBackups(env, db);
      await runDueGoogleDriveBackups(env, db);
      await runDueAnalyticsPdfUploads(env, db);
    } catch (error) {
      console.error('Scheduled upload run failed', databaseErrorMessage(error));
    } finally {
      db.close();
    }
  },
};

type TelegramBackupFrequency = 'daily' | 'weekly' | 'monthly';
type AnalyticsPdfDestination = 'telegram' | 'googleDrive';
type AnalyticsPdfReportVariant = 'summary' | 'transactionHistory';
type AnalyticsReportFormat = 'pdf' | 'xlsx' | 'txt';
type AnalyticsPdfDateFilter = 'today' | 'thisWeek' | 'thisMonth' | 'thisYear' | 'allTime' | 'custom';

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
    const newUserId = crypto.randomUUID();
    const [result] = await db.batch([
      {
        sql: `INSERT INTO users(id, username, password_hash, created_at, updated_at) VALUES (?, ?, ?, ?, ?)
              ON CONFLICT(username) DO NOTHING`,
        args: [newUserId, username, await hashPassword(password, env.JWT_SECRET), now, now],
      },
      { sql: `INSERT OR REPLACE INTO worker_state(key, value) VALUES ('registration_closed', '1')`, args: [] },
    ], 'write');
    if (!result.rowsAffected) throw new HttpError(409, 'Duplicate username. That username is already in use.');
    await db.execute({
      sql: `INSERT OR IGNORE INTO worker_state(key, value) VALUES ('deployment_owner_user_id', ?)`,
      args: [newUserId],
    });
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
      ...['profile_media_chunks', 'profile_media', 'analytics_pdf_schedules', 'analytics_upload_settings', 'google_drive_backup_settings', 'telegram_backup_settings', 'processed_operations', 'sync_changes', 'sync_entities', 'refresh_tokens', 'devices'].map(table => ({ sql: `DELETE FROM ${table} WHERE user_id = ?`, args: [userId] })),
      { sql: 'DELETE FROM users WHERE id = ?', args: [userId] },
    ], 'write');
    if (!results[results.length - 1].rowsAffected) throw new HttpError(404, 'Account no longer exists.');
    const owner = await db.execute({
      sql: `SELECT value FROM worker_state WHERE key = 'deployment_owner_user_id'`,
      args: [],
    });
    if (String(owner.rows[0]?.value ?? '') === userId) {
      await db.batch(
        [
          { sql: `DELETE FROM worker_state WHERE key = 'deployment_owner_user_id'`, args: [] },
          { sql: `DELETE FROM worker_state WHERE key = 'deployment_recovery_ciphertext'`, args: [] },
          { sql: `DELETE FROM worker_state WHERE key = 'deployment_recovery_iv'`, args: [] },
          { sql: `DELETE FROM worker_state WHERE key = 'deployment_recovery_updated_at'`, args: [] },
        ],
        'write',
      );
    }
    return privateJson({ ok: true, message: 'Account deleted.' });
  }
  throw new HttpError(405, 'Method not allowed.');
}

function profilePassword(value: unknown): string {
  if (typeof value !== 'string' || value.length > 256) throw new HttpError(400, 'Password must be 8-256 characters.');
  validatePassword(value);
  return value;
}

type GoogleDriveAnalyticsSettings = {
  userId: string;
  clientId: string;
  clientSecretConfigured: boolean;
  encryptedClientSecret: string;
  clientSecretIv: string;
  connected: boolean;
  encryptedRefreshToken: string;
  refreshTokenIv: string;
  accountEmail: string;
  folderId: string;
  connectedAt: number | null;
  lastUploadAt: number | null;
  lastError: string | null;
};

type AnalyticsPdfScheduleSettings = {
  userId: string;
  destination: AnalyticsPdfDestination;
  enabled: boolean;
  reportVariant: AnalyticsPdfReportVariant;
  fileFormat: AnalyticsReportFormat;
  dateFilter: AnalyticsPdfDateFilter;
  customStart: string | null;
  customEnd: string | null;
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

type GoogleDriveBackupSettings = {
  userId: string;
  enabled: boolean;
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
  const telegramPdfSchedule = await readAnalyticsPdfSchedule(db, auth.userId, 'telegram');
  if (telegramPdfSchedule.enabled && (!encryptedToken || !chatId)) {
    throw new HttpError(409, 'Keep the Telegram bot token and destination configured while automatic Telegram report uploads are enabled.');
  }

  await assertScheduledUploadSeparation(db, auth.userId, undefined, { enabled, hour, minute });

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

type CloudFinanceSnapshot = {
  database: Record<string, Array<Record<string, unknown>>>;
  preferences: Record<string, unknown>;
  financeRecordCount: number;
};

async function readCloudFinanceSnapshot(db: Client, userId: string): Promise<CloudFinanceSnapshot> {
  const database: Record<string, Array<Record<string, unknown>>> = {};
  for (const table of telegramBackupEntityTables) database[table] = [];
  let preferences: Record<string, unknown> = {};

  const entityRows = (await db.execute({
    sql: `SELECT entity_type, entity_id, payload_json
          FROM sync_entities
          WHERE user_id = ? AND deleted_at IS NULL
          ORDER BY entity_type, entity_id`,
    args: [userId],
  })).rows;
  applyTelegramBackupRows(entityRows, database, value => { preferences = value; });

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

  return {
    database,
    preferences,
    financeRecordCount: telegramBackupFinanceRecordCount(database),
  };
}

async function buildTelegramBackupFile(db: Client, userId: string): Promise<{ fileName: string; contents: string }> {
  const snapshot = await readCloudFinanceSnapshot(db, userId);
  const { database, preferences, financeRecordCount } = snapshot;
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

async function buildGoogleDriveBackupFile(db: Client, userId: string): Promise<{ fileName: string; contents: string }> {
  const snapshot = await readCloudFinanceSnapshot(db, userId);
  const { database, preferences, financeRecordCount } = snapshot;
  if (financeRecordCount === 0) {
    throw new HttpError(
      409,
      'The cloud copy contains no finance records, so an empty Google Drive backup was not uploaded. Open Koinly on a device with your data, use Upload local changes once, then create the backup again.',
    );
  }
  const createdAt = new Date();
  const recordCounts = Object.fromEntries(telegramBackupEntityTables.map(table => [table, database[table].length]));
  const payload = {
    version: 7,
    backup_type: 'google-drive-cloud',
    created_at: createdAt.toISOString(),
    database,
    preferences,
    record_counts: recordCounts,
    finance_record_count: financeRecordCount,
  };
  const fileName = `koinly_drive_${compactUtcTimestamp(createdAt)}.koinlybackup`;
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
  await sendTelegramDocument(
    token,
    chatId,
    fileName,
    new Blob([contents], { type: 'application/octet-stream' }),
    `Koinly cloud backup\n${new Date().toISOString().replace('T', ' ').replace('.000Z', ' UTC')}`,
  );
}

async function sendTelegramAnalyticsDocument(
  token: string,
  chatId: string,
  fileName: string,
  bytes: Uint8Array<ArrayBuffer>,
  caption: string,
  mimeType = analyticsReportMimeType(fileName),
): Promise<void> {
  if (bytes.byteLength > analyticsReportMaxBytes) throw new HttpError(413, 'Analytics report must be 10 MB or smaller.');
  await sendTelegramDocument(token, chatId, fileName, new Blob([bytes], { type: mimeType }), caption);
}

async function sendTelegramDocument(
  token: string,
  chatId: string,
  fileName: string,
  document: Blob,
  caption: string,
): Promise<void> {
  for (let attempt = 1; attempt <= 3; attempt += 1) {
    try {
      const form = new FormData();
      form.set('chat_id', chatId);
      form.set('caption', caption.slice(0, 1024));
      form.set('document', document, fileName);
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

async function googleDriveBackupSettings(db: Client, auth: AuthContext): Promise<Response> {
  return privateJson({ ok: true, settings: publicGoogleDriveBackupSettings(await readGoogleDriveBackupSettings(db, auth.userId)) });
}

async function saveGoogleDriveBackupSettings(request: Request, db: Client, auth: AuthContext): Promise<Response> {
  const body = await readJson(request);
  const existing = await readGoogleDriveBackupSettings(db, auth.userId);
  const enabled = body.enabled === true;
  const frequency = normalizeTelegramBackupFrequency(body.frequency ?? existing.frequency);
  const hour = integerInRange(body.hour, existing.hour, 0, 23, 'hour');
  const minute = integerInRange(body.minute, existing.minute, 0, 59, 'minute');
  const weekday = integerInRange(body.weekday, existing.weekday, 1, 7, 'weekday');
  const monthDay = integerInRange(body.monthDay, existing.monthDay, 1, 31, 'monthDay');
  const timezoneOffsetMinutes = integerInRange(body.timezoneOffsetMinutes, existing.timezoneOffsetMinutes, -840, 840, 'timezoneOffsetMinutes');
  if (enabled) {
    const drive = await readGoogleDriveAnalyticsSettings(db, auth.userId);
    if (!drive.connected) throw new HttpError(400, 'Connect Google Drive in Settings > Credential before enabling cloud backups.');
  }
  const candidate: GoogleDriveBackupSettings = {
    userId: auth.userId,
    enabled,
    frequency,
    hour,
    minute,
    weekday,
    monthDay,
    timezoneOffsetMinutes,
    nextDueAt: enabled ? nextTelegramBackupDueAt({ frequency, hour, minute, weekday, monthDay, timezoneOffsetMinutes }, Date.now()) : null,
    lastSentAt: existing.lastSentAt,
    lastAttemptAt: existing.lastAttemptAt,
    lastError: null,
  };
  await assertScheduledUploadSeparation(db, auth.userId, undefined, undefined, candidate);
  const now = Date.now();
  await db.execute({
    sql: `INSERT INTO google_drive_backup_settings(
            user_id, enabled, frequency, hour, minute, weekday, month_day, timezone_offset_minutes,
            next_due_at, last_sent_at, last_attempt_at, last_error, updated_at
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT(user_id) DO UPDATE SET
            enabled = excluded.enabled,
            frequency = excluded.frequency,
            hour = excluded.hour,
            minute = excluded.minute,
            weekday = excluded.weekday,
            month_day = excluded.month_day,
            timezone_offset_minutes = excluded.timezone_offset_minutes,
            next_due_at = excluded.next_due_at,
            last_error = NULL,
            updated_at = excluded.updated_at`,
    args: [auth.userId, enabled ? 1 : 0, frequency, hour, minute, weekday, monthDay, timezoneOffsetMinutes,
      candidate.nextDueAt, existing.lastSentAt, existing.lastAttemptAt, null, now],
  });
  return privateJson({ ok: true, settings: publicGoogleDriveBackupSettings(await readGoogleDriveBackupSettings(db, auth.userId)), minimumSpacingMinutes: 5 });
}

async function sendGoogleDriveBackupNow(env: Env, db: Client, auth: AuthContext): Promise<Response> {
  const drive = await readGoogleDriveAnalyticsSettings(db, auth.userId);
  if (!drive.connected) throw new HttpError(400, 'Connect Google Drive in Settings > Credential first.');
  const now = Date.now();
  await db.execute({
    sql: `INSERT INTO google_drive_backup_settings(user_id, updated_at)
          VALUES (?, ?)
          ON CONFLICT(user_id) DO NOTHING`,
    args: [auth.userId, now],
  });
  const settings = await readGoogleDriveBackupSettings(db, auth.userId);
  const result = await deliverGoogleDriveBackupForUser(env, db, auth.userId, settings, false);
  return privateJson({ ok: true, ...result, settings: publicGoogleDriveBackupSettings(await readGoogleDriveBackupSettings(db, auth.userId)) });
}

async function runDueGoogleDriveBackups(env: Env, db: Client): Promise<void> {
  const now = Date.now();
  const rows = (await db.execute({
    sql: `SELECT user_id, enabled, frequency, hour, minute, weekday, month_day, timezone_offset_minutes,
                 next_due_at, last_sent_at, last_attempt_at, last_error
          FROM google_drive_backup_settings
          WHERE enabled = 1 AND next_due_at IS NOT NULL AND next_due_at <= ?
          ORDER BY next_due_at
          LIMIT 20`,
    args: [now],
  })).rows;
  for (const row of rows) {
    const settings = googleDriveBackupSettingsFromRow(row);
    if (settings.nextDueAt == null) continue;
    const claimedDueAt = settings.nextDueAt;
    const nextDueAt = nextTelegramBackupDueAt(settings, now + 60_000);
    const claimed = await db.execute({
      sql: `UPDATE google_drive_backup_settings
            SET next_due_at = ?, last_attempt_at = ?, updated_at = ?
            WHERE user_id = ? AND enabled = 1 AND next_due_at = ?`,
      args: [nextDueAt, now, now, settings.userId, claimedDueAt],
    });
    if (claimed.rowsAffected !== 1) continue;
    settings.nextDueAt = nextDueAt;
    settings.lastAttemptAt = now;
    try {
      await deliverGoogleDriveBackupForUser(env, db, settings.userId, settings, true);
    } catch (error) {
      console.error('Google Drive backup delivery failed', { userId: settings.userId, error: safeExternalUploadError(error) });
    }
  }
}

async function deliverGoogleDriveBackupForUser(
  env: Env,
  db: Client,
  userId: string,
  settings: GoogleDriveBackupSettings,
  scheduled: boolean,
): Promise<{ fileName: string; uploadedAt: number }> {
  const attemptedAt = Date.now();
  if (!scheduled) {
    await db.execute({
      sql: 'UPDATE google_drive_backup_settings SET last_attempt_at = ?, last_error = NULL, updated_at = ? WHERE user_id = ?',
      args: [attemptedAt, attemptedAt, userId],
    });
  }
  try {
    const drive = await readGoogleDriveAnalyticsSettings(db, userId);
    if (!drive.connected) throw new HttpError(400, 'Google Drive is no longer connected.');
    const accessToken = await googleDriveAccessToken(env, drive);
    const folder = await resolveGoogleBackupFolder(accessToken, drive.folderId);
    const { fileName, contents } = await buildGoogleDriveBackupFile(db, userId);
    const bytes = new Uint8Array(enc.encode(contents));
    await googleDriveUploadDocument(accessToken, folder.id, fileName, bytes, 'application/octet-stream');
    const uploadedAt = Date.now();
    await db.execute({
      sql: `UPDATE google_drive_backup_settings
            SET last_sent_at = ?, last_attempt_at = ?, last_error = NULL, updated_at = ? WHERE user_id = ?`,
      args: [uploadedAt, attemptedAt, uploadedAt, userId],
    });
    return { fileName, uploadedAt };
  } catch (error) {
    const message = safeExternalUploadError(error);
    const failedAt = Date.now();
    if (error instanceof HttpError && error.status === 401) {
      await db.batch([
        {
          sql: `UPDATE analytics_upload_settings
                SET google_refresh_token_encrypted = NULL, google_refresh_token_iv = NULL,
                    google_account_email = '', google_connected_at = NULL, google_last_error = ?, updated_at = ?
                WHERE user_id = ?`,
          args: [message, failedAt, userId],
        },
        {
          sql: `UPDATE google_drive_backup_settings
                SET enabled = 0, next_due_at = NULL, last_attempt_at = ?, last_error = ?, updated_at = ?
                WHERE user_id = ?`,
          args: [attemptedAt, message, failedAt, userId],
        },
      ], 'write');
    } else {
      await db.execute({
        sql: `UPDATE google_drive_backup_settings
              SET last_attempt_at = ?, last_error = ?, updated_at = ? WHERE user_id = ?`,
        args: [attemptedAt, message, failedAt, userId],
      });
    }
    if (error instanceof HttpError) throw error;
    throw new HttpError(502, message);
  }
}

async function readGoogleDriveBackupSettings(db: Client, userId: string): Promise<GoogleDriveBackupSettings> {
  const row = (await db.execute({
    sql: `SELECT user_id, enabled, frequency, hour, minute, weekday, month_day, timezone_offset_minutes,
                 next_due_at, last_sent_at, last_attempt_at, last_error
          FROM google_drive_backup_settings WHERE user_id = ?`,
    args: [userId],
  })).rows[0];
  if (!row) {
    return {
      userId,
      enabled: false,
      frequency: 'daily',
      hour: 2,
      minute: 5,
      weekday: 7,
      monthDay: 1,
      timezoneOffsetMinutes: 0,
      nextDueAt: null,
      lastSentAt: null,
      lastAttemptAt: null,
      lastError: null,
    };
  }
  return googleDriveBackupSettingsFromRow(row);
}

function googleDriveBackupSettingsFromRow(row: Record<string, unknown>): GoogleDriveBackupSettings {
  return {
    userId: String(row.user_id ?? ''),
    enabled: Number(row.enabled ?? 0) === 1,
    frequency: normalizeTelegramBackupFrequency(row.frequency),
    hour: integerInRange(row.hour, 2, 0, 23, 'hour'),
    minute: integerInRange(row.minute, 5, 0, 59, 'minute'),
    weekday: integerInRange(row.weekday, 7, 1, 7, 'weekday'),
    monthDay: integerInRange(row.month_day, 1, 1, 31, 'monthDay'),
    timezoneOffsetMinutes: integerInRange(row.timezone_offset_minutes, 0, -840, 840, 'timezoneOffsetMinutes'),
    nextDueAt: nullableInteger(row.next_due_at),
    lastSentAt: nullableInteger(row.last_sent_at),
    lastAttemptAt: nullableInteger(row.last_attempt_at),
    lastError: row.last_error == null ? null : String(row.last_error),
  };
}

function publicGoogleDriveBackupSettings(settings: GoogleDriveBackupSettings): Record<string, unknown> {
  return {
    enabled: settings.enabled,
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

const analyticsGoogleDriveFolderName = 'Koinly Analytics';
const backupGoogleDriveFolderName = 'Koinly Backup';
const analyticsReportMaxBytes = 10 * 1024 * 1024;

async function googleDriveAnalyticsSettings(db: Client, auth: AuthContext): Promise<Response> {
  return privateJson({
    ok: true,
    settings: publicGoogleDriveAnalyticsSettings(await readGoogleDriveAnalyticsSettings(db, auth.userId)),
  });
}

async function saveGoogleDriveAnalyticsSettings(
  request: Request,
  env: Env,
  db: Client,
  auth: AuthContext,
): Promise<Response> {
  const body = await readJson(request);
  const existing = await readGoogleDriveAnalyticsSettings(db, auth.userId);
  const clientId = String(body.clientId ?? existing.clientId).trim();
  if (!/^[A-Za-z0-9._-]{10,220}\.apps\.googleusercontent\.com$/.test(clientId)) {
    throw new HttpError(400, 'Enter a valid Google OAuth Web application Client ID.');
  }

  const suppliedSecret = String(body.clientSecret ?? '').trim();
  if (suppliedSecret.length > 512) throw new HttpError(400, 'Google OAuth Client Secret is too long.');
  const folderId = normalizeGoogleDriveFolderId(body.folderId ?? existing.folderId);
  let encryptedClientSecret = existing.encryptedClientSecret;
  let clientSecretIv = existing.clientSecretIv;
  if (suppliedSecret) {
    const encrypted = await encryptWorkerSecret(env.JWT_SECRET, 'google-drive-client-secret', suppliedSecret);
    encryptedClientSecret = encrypted.ciphertext;
    clientSecretIv = encrypted.iv;
  }
  if (!encryptedClientSecret) {
    throw new HttpError(400, 'Enter the Google OAuth Web application Client Secret.');
  }

  const clientChanged = existing.clientId.length > 0 && existing.clientId !== clientId;
  const folderChanged = existing.folderId !== folderId;
  const authorizationChanged = clientChanged || folderChanged;
  const now = Date.now();
  await db.execute({
    sql: `INSERT INTO analytics_upload_settings(
            user_id, google_client_id, google_client_secret_encrypted, google_client_secret_iv,
            google_refresh_token_encrypted, google_refresh_token_iv, google_account_email, google_folder_id,
            google_connected_at, google_last_upload_at, google_last_error, updated_at
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT(user_id) DO UPDATE SET
            google_client_id = excluded.google_client_id,
            google_client_secret_encrypted = excluded.google_client_secret_encrypted,
            google_client_secret_iv = excluded.google_client_secret_iv,
            google_refresh_token_encrypted = excluded.google_refresh_token_encrypted,
            google_refresh_token_iv = excluded.google_refresh_token_iv,
            google_account_email = excluded.google_account_email,
            google_folder_id = excluded.google_folder_id,
            google_connected_at = excluded.google_connected_at,
            google_last_upload_at = excluded.google_last_upload_at,
            google_last_error = NULL,
            updated_at = excluded.updated_at`,
    args: [
      auth.userId,
      clientId,
      encryptedClientSecret,
      clientSecretIv,
      authorizationChanged ? null : (existing.encryptedRefreshToken || null),
      authorizationChanged ? null : (existing.refreshTokenIv || null),
      authorizationChanged ? '' : existing.accountEmail,
      folderId,
      authorizationChanged ? null : existing.connectedAt,
      authorizationChanged ? null : existing.lastUploadAt,
      null,
      now,
    ],
  });
  return privateJson({
    ok: true,
    settings: publicGoogleDriveAnalyticsSettings(await readGoogleDriveAnalyticsSettings(db, auth.userId)),
  });
}

async function googleDriveAnalyticsConnectUrl(
  request: Request,
  env: Env,
  db: Client,
  auth: AuthContext,
): Promise<Response> {
  const settings = await readGoogleDriveAnalyticsSettings(db, auth.userId);
  if (!settings.clientId || !settings.encryptedClientSecret) {
    throw new HttpError(400, 'Save your Google OAuth Client ID and Client Secret first.');
  }
  const redirectUri = `${new URL(request.url).origin}/v1/analytics-upload/google-drive/callback`;
  const state = await signToken(env.JWT_SECRET, {
    scope: 'google-drive-analytics-connect',
    sub: auth.userId,
    exp: Math.floor(Date.now() / 1000) + 10 * 60,
    nonce: b64urlBytes(crypto.getRandomValues(new Uint8Array(18))),
  });
  const authorization = new URL('https://accounts.google.com/o/oauth2/v2/auth');
  authorization.searchParams.set('client_id', settings.clientId);
  authorization.searchParams.set('redirect_uri', redirectUri);
  authorization.searchParams.set('response_type', 'code');
  authorization.searchParams.set('access_type', 'offline');
  authorization.searchParams.set('prompt', 'consent');
  authorization.searchParams.set('include_granted_scopes', 'true');
  authorization.searchParams.set('scope', settings.folderId
    ? 'openid email https://www.googleapis.com/auth/drive'
    : 'openid email https://www.googleapis.com/auth/drive.file');
  authorization.searchParams.set('state', state);
  return privateJson({ ok: true, authorizationUrl: authorization.toString(), redirectUri });
}

async function googleDriveAnalyticsCallback(request: Request, env: Env, db: Client): Promise<Response> {
  const url = new URL(request.url);
  try {
    const oauthError = cleanText(url.searchParams.get('error_description') || url.searchParams.get('error'), 240);
    if (oauthError) throw new HttpError(400, `Google authorization was not completed: ${oauthError}`);
    const code = String(url.searchParams.get('code') ?? '').trim();
    const stateToken = String(url.searchParams.get('state') ?? '').trim();
    if (!code || !stateToken) throw new HttpError(400, 'Google did not return the required authorization code.');
    const state = await verifyToken(env.JWT_SECRET, stateToken);
    if (state.scope !== 'google-drive-analytics-connect') throw new HttpError(401, 'Invalid Google Drive connection state.');
    const userId = String(state.sub ?? '');
    if (!userId) throw new HttpError(401, 'Invalid Google Drive connection state.');

    const settings = await readGoogleDriveAnalyticsSettings(db, userId);
    if (!settings.clientId || !settings.encryptedClientSecret) {
      throw new HttpError(409, 'Google Drive credentials are no longer configured in Koinly.');
    }
    const clientSecret = await decryptWorkerSecret(
      env.JWT_SECRET,
      'google-drive-client-secret',
      settings.encryptedClientSecret,
      settings.clientSecretIv,
      'The saved Google OAuth Client Secret cannot be decrypted. Re-enter it in Koinly.',
    );
    const redirectUri = `${url.origin}/v1/analytics-upload/google-drive/callback`;
    const tokenResponse = await fetch('https://oauth2.googleapis.com/token', {
      method: 'POST',
      headers: { 'content-type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        code,
        client_id: settings.clientId,
        client_secret: clientSecret,
        redirect_uri: redirectUri,
        grant_type: 'authorization_code',
      }).toString(),
    });
    const tokenText = await tokenResponse.text();
    const tokenData = parseJsonRecord(tokenText);
    if (!tokenResponse.ok) {
      throw new HttpError(502, googleOAuthFailure(tokenResponse.status, tokenData));
    }
    const refreshToken = String(tokenData.refresh_token ?? '').trim();
    const accessToken = String(tokenData.access_token ?? '').trim();
    if (!refreshToken) {
      throw new HttpError(409, 'Google did not issue an offline refresh token. Remove Koinly from your Google account permissions, then connect again.');
    }
    if (!accessToken) throw new HttpError(502, 'Google did not return an access token.');

    let accountEmail = '';
    try {
      const userResponse = await fetch('https://openidconnect.googleapis.com/v1/userinfo', {
        headers: { authorization: `Bearer ${accessToken}`, accept: 'application/json' },
      });
      if (userResponse.ok) {
        const userInfo = parseJsonRecord(await userResponse.text());
        accountEmail = cleanText(userInfo.email, 240);
      }
    } catch {}

    if (settings.folderId) {
      await googleDriveFolderById(accessToken, settings.folderId);
    }

    const encryptedRefreshToken = await encryptWorkerSecret(env.JWT_SECRET, 'google-drive-refresh-token', refreshToken);
    const now = Date.now();
    await db.execute({
      sql: `UPDATE analytics_upload_settings
            SET google_refresh_token_encrypted = ?, google_refresh_token_iv = ?, google_account_email = ?,
                google_connected_at = ?, google_last_error = NULL, updated_at = ?
            WHERE user_id = ?`,
      args: [encryptedRefreshToken.ciphertext, encryptedRefreshToken.iv, accountEmail, now, now, userId],
    });
    return googleDriveCallbackPage(
      'Google Drive connected',
      accountEmail ? `Koinly can now upload Analytics reports to ${accountEmail}. You can return to the app.` : 'Koinly can now upload Analytics reports to Google Drive. You can return to the app.',
      true,
      200,
    );
  } catch (error) {
    const status = error instanceof HttpError ? error.status : 500;
    const message = error instanceof HttpError ? error.message : 'Google Drive connection failed. Return to Koinly and try again.';
    return googleDriveCallbackPage('Google Drive connection failed', message, false, status);
  }
}

async function disconnectGoogleDriveAnalytics(env: Env, db: Client, auth: AuthContext): Promise<Response> {
  const settings = await readGoogleDriveAnalyticsSettings(db, auth.userId);
  if (settings.encryptedRefreshToken) {
    try {
      const refreshToken = await decryptWorkerSecret(
        env.JWT_SECRET,
        'google-drive-refresh-token',
        settings.encryptedRefreshToken,
        settings.refreshTokenIv,
        'The saved Google Drive authorization cannot be decrypted.',
      );
      await fetch('https://oauth2.googleapis.com/revoke', {
        method: 'POST',
        headers: { 'content-type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams({ token: refreshToken }).toString(),
      });
    } catch {}
  }
  const now = Date.now();
  await db.batch([
    {
      sql: `UPDATE analytics_upload_settings
            SET google_refresh_token_encrypted = NULL, google_refresh_token_iv = NULL,
                google_account_email = '', google_connected_at = NULL, google_last_error = NULL, updated_at = ?
            WHERE user_id = ?`,
      args: [now, auth.userId],
    },
    {
      sql: `UPDATE analytics_pdf_schedules
            SET enabled = 0, next_due_at = NULL, last_error = NULL, updated_at = ?
            WHERE user_id = ? AND destination = 'googleDrive'`,
      args: [now, auth.userId],
    },
    {
      sql: `UPDATE google_drive_backup_settings
            SET enabled = 0, next_due_at = NULL, last_error = NULL, updated_at = ?
            WHERE user_id = ?`,
      args: [now, auth.userId],
    },
  ], 'write');
  return privateJson({
    ok: true,
    settings: publicGoogleDriveAnalyticsSettings(await readGoogleDriveAnalyticsSettings(db, auth.userId)),
  });
}

async function uploadAnalyticsPdfToTelegram(request: Request, env: Env, db: Client, auth: AuthContext): Promise<Response> {
  const report = await analyticsReportRequest(request);
  const telegram = await readTelegramBackupSettings(db, auth.userId);
  if (!telegram.encryptedToken || !telegram.chatId) {
    throw new HttpError(400, 'Configure Telegram credentials in Settings > Credential first.');
  }
  const token = await decryptTelegramBotToken(env.JWT_SECRET, telegram.encryptedToken, telegram.tokenIv);
  const caption = report.caption || `Koinly Analytics\n${new Date().toISOString().replace('T', ' ').replace('.000Z', ' UTC')}`;
  await sendTelegramAnalyticsDocument(token, telegram.chatId, report.fileName, report.bytes, caption, report.mimeType);
  return privateJson({ ok: true, destination: 'telegram', fileName: report.fileName, format: report.format, sentAt: Date.now() });
}

async function uploadAnalyticsPdfToGoogleDrive(request: Request, env: Env, db: Client, auth: AuthContext): Promise<Response> {
  const report = await analyticsReportRequest(request);
  const settings = await readGoogleDriveAnalyticsSettings(db, auth.userId);
  if (!settings.connected) throw new HttpError(400, 'Connect Google Drive in Settings > Credential first.');
  const attemptedAt = Date.now();
  try {
    const accessToken = await googleDriveAccessToken(env, settings);
    const folder = await resolveGoogleAnalyticsFolder(accessToken, settings.folderId);
    const uploaded = await googleDriveUploadDocument(accessToken, folder.id, report.fileName, report.bytes, report.mimeType);
    const completedAt = Date.now();
    await db.execute({
      sql: `UPDATE analytics_upload_settings
            SET google_last_upload_at = ?, google_last_error = NULL, updated_at = ? WHERE user_id = ?`,
      args: [completedAt, completedAt, auth.userId],
    });
    return privateJson({
      ok: true,
      destination: 'google-drive',
      fileName: report.fileName,
      folderName: folder.name,
      folderId: folder.id,
      fileId: uploaded.id,
      webViewLink: uploaded.webViewLink,
      uploadedAt: completedAt,
    });
  } catch (error) {
    const message = safeExternalUploadError(error);
    if (error instanceof HttpError && error.status === 401) {
      await db.execute({
        sql: `UPDATE analytics_upload_settings
              SET google_refresh_token_encrypted = NULL, google_refresh_token_iv = NULL,
                  google_account_email = '', google_connected_at = NULL, google_last_error = ?, updated_at = ?
              WHERE user_id = ?`,
        args: [message, attemptedAt, auth.userId],
      });
    } else {
      await db.execute({
        sql: `UPDATE analytics_upload_settings SET google_last_error = ?, updated_at = ? WHERE user_id = ?`,
        args: [message, attemptedAt, auth.userId],
      });
    }
    if (error instanceof HttpError) throw error;
    throw new HttpError(502, message);
  }
}

function analyticsReportFormatFromFileName(fileName: string): AnalyticsReportFormat {
  const match = /\.([A-Za-z0-9]+)$/.exec(fileName);
  return normalizeAnalyticsReportFormat(match?.[1] ?? '');
}

function analyticsReportMimeType(value: string | AnalyticsReportFormat): string {
  const format = value === 'pdf' || value === 'xlsx' || value === 'txt' ? value : analyticsReportFormatFromFileName(value);
  if (format === 'pdf') return 'application/pdf';
  if (format === 'xlsx') return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
  return 'text/plain';
}

function indexOfAscii(bytes: Uint8Array<ArrayBuffer>, needle: string): number {
  const target = new TextEncoder().encode(needle);
  if (target.byteLength === 0 || target.byteLength > bytes.byteLength) return -1;
  outer: for (let offset = 0; offset <= bytes.byteLength - target.byteLength; offset += 1) {
    for (let index = 0; index < target.byteLength; index += 1) {
      if (bytes[offset + index] !== target[index]) continue outer;
    }
    return offset;
  }
  return -1;
}

async function analyticsReportRequest(request: Request): Promise<{ fileName: string; bytes: Uint8Array<ArrayBuffer>; caption: string; format: AnalyticsReportFormat; mimeType: string }> {
  const body = await readJson(request);
  const fileName = cleanText(body.fileName, 140);
  if (!/^[A-Za-z0-9][A-Za-z0-9._ ()-]{0,130}\.(pdf|xlsx|txt)$/i.test(fileName)) {
    throw new HttpError(400, 'Analytics report filename must end in .pdf, .xlsx, or .txt.');
  }
  const format = analyticsReportFormatFromFileName(fileName);
  const contentBase64 = typeof body.contentBase64 === 'string' ? body.contentBase64 : '';
  if (!contentBase64 || contentBase64.length > Math.ceil(analyticsReportMaxBytes * 4 / 3) + 16) {
    throw new HttpError(413, 'Analytics report must be 10 MB or smaller.');
  }
  let bytes: Uint8Array<ArrayBuffer>;
  try {
    bytes = bytesFromBase64(contentBase64);
  } catch {
    throw new HttpError(400, 'Analytics report payload is invalid.');
  }
  if (bytes.byteLength === 0 || bytes.byteLength > analyticsReportMaxBytes) {
    throw new HttpError(413, 'Analytics report must be 10 MB or smaller.');
  }
  if (format === 'pdf') {
    if (bytes.byteLength < 5 || String.fromCharCode(...Array.from(bytes.subarray(0, 5))) !== '%PDF-') {
      throw new HttpError(400, 'The uploaded Analytics document is not a valid PDF.');
    }
  } else if (format === 'xlsx') {
    const hasZipHeader = bytes.byteLength >= 4 && bytes[0] === 0x50 && bytes[1] === 0x4b && bytes[2] === 0x03 && bytes[3] === 0x04;
    const workbookIndex = indexOfAscii(bytes, 'xl/workbook.xml');
    const contentTypesIndex = indexOfAscii(bytes, '[Content_Types].xml');
    if (!hasZipHeader || workbookIndex < 0 || contentTypesIndex < 0) {
      throw new HttpError(400, 'The uploaded Analytics document is not a valid XLSX workbook.');
    }
  } else {
    try {
      const decoded = new TextDecoder('utf-8', { fatal: true }).decode(bytes);
      if (decoded.includes('\u0000')) throw new Error('binary');
    } catch {
      throw new HttpError(400, 'The uploaded Analytics document is not valid UTF-8 text.');
    }
  }
  return { fileName, bytes, caption: cleanText(body.caption, 512), format, mimeType: analyticsReportMimeType(format) };
}

async function readGoogleDriveAnalyticsSettings(db: Client, userId: string): Promise<GoogleDriveAnalyticsSettings> {
  const row = (await db.execute({
    sql: `SELECT user_id, google_client_id, google_client_secret_encrypted, google_client_secret_iv,
                 google_refresh_token_encrypted, google_refresh_token_iv, google_account_email, google_folder_id,
                 google_connected_at, google_last_upload_at, google_last_error
          FROM analytics_upload_settings WHERE user_id = ?`,
    args: [userId],
  })).rows[0];
  if (!row) {
    return {
      userId,
      clientId: '',
      clientSecretConfigured: false,
      encryptedClientSecret: '',
      clientSecretIv: '',
      connected: false,
      encryptedRefreshToken: '',
      refreshTokenIv: '',
      accountEmail: '',
      folderId: '',
      connectedAt: null,
      lastUploadAt: null,
      lastError: null,
    };
  }
  return googleDriveAnalyticsSettingsFromRow(row);
}

function googleDriveAnalyticsSettingsFromRow(row: Record<string, unknown>): GoogleDriveAnalyticsSettings {
  const encryptedRefreshToken = String(row.google_refresh_token_encrypted ?? '');
  return {
    userId: String(row.user_id ?? ''),
    clientId: String(row.google_client_id ?? ''),
    clientSecretConfigured: Boolean(row.google_client_secret_encrypted),
    encryptedClientSecret: String(row.google_client_secret_encrypted ?? ''),
    clientSecretIv: String(row.google_client_secret_iv ?? ''),
    connected: Boolean(encryptedRefreshToken),
    encryptedRefreshToken,
    refreshTokenIv: String(row.google_refresh_token_iv ?? ''),
    accountEmail: String(row.google_account_email ?? ''),
    folderId: String(row.google_folder_id ?? ''),
    connectedAt: nullableInteger(row.google_connected_at),
    lastUploadAt: nullableInteger(row.google_last_upload_at),
    lastError: row.google_last_error == null ? null : String(row.google_last_error),
  };
}

function publicGoogleDriveAnalyticsSettings(settings: GoogleDriveAnalyticsSettings): Record<string, unknown> {
  return {
    clientId: settings.clientId,
    clientSecretConfigured: settings.clientSecretConfigured,
    connected: settings.connected,
    accountEmail: settings.accountEmail,
    folderId: settings.folderId,
    folderName: settings.folderId ? 'Selected Google Drive folder' : analyticsGoogleDriveFolderName,
    connectedAt: settings.connectedAt,
    lastUploadAt: settings.lastUploadAt,
    lastError: settings.lastError,
  };
}

function normalizeGoogleDriveFolderId(value: unknown): string {
  const folderId = String(value ?? '').trim();
  if (!folderId) return '';
  if (!/^[A-Za-z0-9_-]{10,200}$/.test(folderId)) {
    throw new HttpError(400, 'Enter a valid Google Drive folder ID.');
  }
  return folderId;
}

function normalizeAnalyticsPdfDestination(value: unknown): AnalyticsPdfDestination {
  const normalized = String(value ?? '').trim();
  if (normalized === 'telegram' || normalized === 'googleDrive') return normalized;
  throw new HttpError(400, 'Analytics report destination must be Telegram or Google Drive.');
}

function normalizeAnalyticsPdfReportVariant(value: unknown): AnalyticsPdfReportVariant {
  const normalized = String(value ?? '').trim();
  if (normalized === 'summary' || normalized === 'transactionHistory') return normalized;
  throw new HttpError(400, 'Analytics report type must be Summary or Transaction history.');
}

function normalizeAnalyticsReportFormat(value: unknown): AnalyticsReportFormat {
  const normalized = String(value ?? '').trim().toLowerCase();
  if (normalized === 'pdf' || normalized === 'xlsx' || normalized === 'txt') return normalized;
  throw new HttpError(400, 'Analytics report format must be PDF, XLSX, or TXT.');
}

function normalizeAnalyticsPdfDateFilter(value: unknown): AnalyticsPdfDateFilter {
  const normalized = String(value ?? '').trim();
  if (normalized === 'today' || normalized === 'thisWeek' || normalized === 'thisMonth' || normalized === 'thisYear' || normalized === 'allTime' || normalized === 'custom') {
    return normalized;
  }
  throw new HttpError(400, 'Automatic report date filter must be Today, This Week, This Month, This Year, All Time, or Custom Range.');
}

function normalizeAnalyticsCustomDate(value: unknown): string | null {
  const raw = String(value ?? '').trim();
  if (!raw) return null;
  if (!/^\d{4}-\d{2}-\d{2}$/.test(raw)) throw new HttpError(400, 'Custom range dates must use YYYY-MM-DD.');
  const [year, month, day] = raw.split('-').map(Number);
  const parsed = new Date(Date.UTC(year, month - 1, day));
  if (parsed.getUTCFullYear() !== year || parsed.getUTCMonth() !== month - 1 || parsed.getUTCDate() !== day) {
    throw new HttpError(400, 'Custom range contains an invalid calendar date.');
  }
  return raw;
}

function compareDateOnly(first: string, second: string): number {
  return first === second ? 0 : first < second ? -1 : 1;
}

function defaultAnalyticsPdfSchedule(userId: string, destination: AnalyticsPdfDestination): AnalyticsPdfScheduleSettings {
  return {
    userId,
    destination,
    enabled: false,
    reportVariant: 'summary',
    fileFormat: 'pdf',
    dateFilter: 'thisMonth',
    customStart: null,
    customEnd: null,
    frequency: 'daily',
    hour: destination === 'telegram' ? 3 : 4,
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

function analyticsPdfScheduleFromRow(row: Record<string, unknown>): AnalyticsPdfScheduleSettings {
  const destination = normalizeAnalyticsPdfDestination(row.destination);
  return {
    userId: String(row.user_id ?? ''),
    destination,
    enabled: Number(row.enabled ?? 0) === 1,
    reportVariant: normalizeAnalyticsPdfReportVariant(row.report_variant),
    fileFormat: normalizeAnalyticsReportFormat(row.file_format ?? 'pdf'),
    dateFilter: normalizeAnalyticsPdfDateFilter(row.date_filter),
    customStart: normalizeAnalyticsCustomDate(row.custom_start),
    customEnd: normalizeAnalyticsCustomDate(row.custom_end),
    frequency: normalizeTelegramBackupFrequency(row.frequency),
    hour: integerInRange(row.hour, destination === 'telegram' ? 3 : 4, 0, 23, 'hour'),
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

async function readAnalyticsPdfSchedule(db: Client, userId: string, destination: AnalyticsPdfDestination): Promise<AnalyticsPdfScheduleSettings> {
  const row = (await db.execute({
    sql: `SELECT user_id, destination, enabled, report_variant, file_format, date_filter, custom_start, custom_end, frequency,
                 hour, minute, weekday, month_day, timezone_offset_minutes, next_due_at,
                 last_sent_at, last_attempt_at, last_error
          FROM analytics_pdf_schedules
          WHERE user_id = ? AND destination = ?`,
    args: [userId, destination],
  })).rows[0];
  return row ? analyticsPdfScheduleFromRow(row) : defaultAnalyticsPdfSchedule(userId, destination);
}

function publicAnalyticsPdfSchedule(settings: AnalyticsPdfScheduleSettings): Record<string, unknown> {
  return {
    destination: settings.destination,
    enabled: settings.enabled,
    reportVariant: settings.reportVariant,
    fileFormat: settings.fileFormat,
    dateFilter: settings.dateFilter,
    customStart: settings.customStart,
    customEnd: settings.customEnd,
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

async function analyticsPdfSchedules(db: Client, auth: AuthContext): Promise<Response> {
  const [telegram, googleDrive] = await Promise.all([
    readAnalyticsPdfSchedule(db, auth.userId, 'telegram'),
    readAnalyticsPdfSchedule(db, auth.userId, 'googleDrive'),
  ]);
  return privateJson({
    ok: true,
    schedules: {
      telegram: publicAnalyticsPdfSchedule(telegram),
      googleDrive: publicAnalyticsPdfSchedule(googleDrive),
    },
    minimumSpacingMinutes: 5,
  });
}

type ScheduledClock = { label: string; hour: number; minute: number; enabled: boolean };

export function scheduledClockDistanceMinutes(first: ScheduledClock, second: ScheduledClock): number {
  const a = first.hour * 60 + first.minute;
  const b = second.hour * 60 + second.minute;
  const direct = Math.abs(a - b);
  return Math.min(direct, 24 * 60 - direct);
}

function formatScheduledClock(clock: ScheduledClock): string {
  return `${String(clock.hour).padStart(2, '0')}:${String(clock.minute).padStart(2, '0')}`;
}

async function assertScheduledUploadSeparation(
  db: Client,
  userId: string,
  candidate?: AnalyticsPdfScheduleSettings,
  telegramBackupCandidate?: Pick<TelegramBackupSettings, 'enabled' | 'hour' | 'minute'>,
  googleDriveBackupCandidate?: Pick<GoogleDriveBackupSettings, 'enabled' | 'hour' | 'minute'>,
): Promise<void> {
  const [telegramSchedule, driveSchedule, storedTelegramBackup, storedDriveBackup] = await Promise.all([
    readAnalyticsPdfSchedule(db, userId, 'telegram'),
    readAnalyticsPdfSchedule(db, userId, 'googleDrive'),
    readTelegramBackupSettings(db, userId),
    readGoogleDriveBackupSettings(db, userId),
  ]);
  const telegram = candidate?.destination === 'telegram' ? candidate : telegramSchedule;
  const drive = candidate?.destination === 'googleDrive' ? candidate : driveSchedule;
  const telegramBackup = telegramBackupCandidate ?? storedTelegramBackup;
  const driveBackup = googleDriveBackupCandidate ?? storedDriveBackup;
  const clocks: ScheduledClock[] = [
    { label: 'Telegram report', hour: telegram.hour, minute: telegram.minute, enabled: telegram.enabled },
    { label: 'Google Drive report', hour: drive.hour, minute: drive.minute, enabled: drive.enabled },
    { label: 'Telegram backup', hour: telegramBackup.hour, minute: telegramBackup.minute, enabled: telegramBackup.enabled },
    { label: 'Google Drive backup', hour: driveBackup.hour, minute: driveBackup.minute, enabled: driveBackup.enabled },
  ].filter(item => item.enabled);

  for (let i = 0; i < clocks.length; i += 1) {
    for (let j = i + 1; j < clocks.length; j += 1) {
      if (scheduledClockDistanceMinutes(clocks[i], clocks[j]) < 5) {
        throw new HttpError(
          409,
          `Automatic uploads must be at least 5 minutes apart. ${clocks[i].label} at ${formatScheduledClock(clocks[i])} conflicts with ${clocks[j].label} at ${formatScheduledClock(clocks[j])}.`,
        );
      }
    }
  }
}

async function saveAnalyticsPdfSchedule(
  request: Request,
  _env: Env,
  db: Client,
  auth: AuthContext,
  pathname: string,
): Promise<Response> {
  const destination = normalizeAnalyticsPdfDestination(pathname.split('/').pop());
  const body = await readJson(request);
  const existing = await readAnalyticsPdfSchedule(db, auth.userId, destination);
  const enabled = body.enabled === true;
  const reportVariant = normalizeAnalyticsPdfReportVariant(body.reportVariant ?? existing.reportVariant);
  const fileFormat = normalizeAnalyticsReportFormat(body.fileFormat ?? existing.fileFormat);
  const dateFilter = normalizeAnalyticsPdfDateFilter(body.dateFilter ?? existing.dateFilter);
  const customStart = normalizeAnalyticsCustomDate(body.customStart ?? existing.customStart);
  const customEnd = normalizeAnalyticsCustomDate(body.customEnd ?? existing.customEnd);
  if (dateFilter === 'custom') {
    if (!customStart || !customEnd) throw new HttpError(400, 'Choose both a custom start date and end date.');
    if (compareDateOnly(customEnd, customStart) < 0) throw new HttpError(400, 'Custom range end date cannot be before the start date.');
  }
  const frequency = normalizeTelegramBackupFrequency(body.frequency ?? existing.frequency);
  const hour = integerInRange(body.hour, existing.hour, 0, 23, 'hour');
  const minute = integerInRange(body.minute, existing.minute, 0, 59, 'minute');
  const weekday = integerInRange(body.weekday, existing.weekday, 1, 7, 'weekday');
  const monthDay = integerInRange(body.monthDay, existing.monthDay, 1, 31, 'monthDay');
  const timezoneOffsetMinutes = integerInRange(body.timezoneOffsetMinutes, existing.timezoneOffsetMinutes, -840, 840, 'timezoneOffsetMinutes');

  if (enabled && destination === 'telegram') {
    const telegram = await readTelegramBackupSettings(db, auth.userId);
    if (!telegram.encryptedToken || !telegram.chatId) {
      throw new HttpError(400, 'Configure Telegram credentials in Settings > Credential before enabling automatic report uploads.');
    }
  }
  if (enabled && destination === 'googleDrive') {
    const drive = await readGoogleDriveAnalyticsSettings(db, auth.userId);
    if (!drive.connected) throw new HttpError(400, 'Connect Google Drive in Settings > Credential before enabling automatic report uploads.');
  }

  const candidate: AnalyticsPdfScheduleSettings = {
    userId: auth.userId,
    destination,
    enabled,
    reportVariant,
    fileFormat,
    dateFilter,
    customStart,
    customEnd,
    frequency,
    hour,
    minute,
    weekday,
    monthDay,
    timezoneOffsetMinutes,
    nextDueAt: enabled
      ? nextScheduledUploadDueAt({ frequency, hour, minute, weekday, monthDay, timezoneOffsetMinutes }, Date.now())
      : null,
    lastSentAt: existing.lastSentAt,
    lastAttemptAt: existing.lastAttemptAt,
    lastError: null,
  };
  await assertScheduledUploadSeparation(db, auth.userId, candidate);

  const now = Date.now();
  await db.execute({
    sql: `INSERT INTO analytics_pdf_schedules(
            user_id, destination, enabled, report_variant, file_format, date_filter, custom_start, custom_end, frequency,
            hour, minute, weekday, month_day, timezone_offset_minutes, next_due_at,
            last_sent_at, last_attempt_at, last_error, updated_at
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT(user_id, destination) DO UPDATE SET
            enabled = excluded.enabled,
            report_variant = excluded.report_variant,
            file_format = excluded.file_format,
            date_filter = excluded.date_filter,
            custom_start = excluded.custom_start,
            custom_end = excluded.custom_end,
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
      auth.userId, destination, enabled ? 1 : 0, reportVariant, fileFormat, dateFilter, customStart, customEnd, frequency,
      hour, minute, weekday, monthDay, timezoneOffsetMinutes, candidate.nextDueAt,
      existing.lastSentAt, existing.lastAttemptAt, null, now,
    ],
  });
  return privateJson({ ok: true, schedule: publicAnalyticsPdfSchedule(await readAnalyticsPdfSchedule(db, auth.userId, destination)), minimumSpacingMinutes: 5 });
}

async function runDueAnalyticsPdfUploads(env: Env, db: Client): Promise<void> {
  const now = Date.now();
  const rows = (await db.execute({
    sql: `SELECT user_id, destination, enabled, report_variant, file_format, date_filter, custom_start, custom_end, frequency,
                 hour, minute, weekday, month_day, timezone_offset_minutes, next_due_at,
                 last_sent_at, last_attempt_at, last_error
          FROM analytics_pdf_schedules
          WHERE enabled = 1 AND next_due_at IS NOT NULL AND next_due_at <= ?
          ORDER BY next_due_at
          LIMIT 20`,
    args: [now],
  })).rows;

  for (const row of rows) {
    const settings = analyticsPdfScheduleFromRow(row);
    if (settings.nextDueAt == null) continue;
    const claimedDueAt = settings.nextDueAt;
    const nextDueAt = nextScheduledUploadDueAt(settings, now + 60_000);
    const claimed = await db.execute({
      sql: `UPDATE analytics_pdf_schedules
            SET next_due_at = ?, last_attempt_at = ?, updated_at = ?
            WHERE user_id = ? AND destination = ? AND enabled = 1 AND next_due_at = ?`,
      args: [nextDueAt, now, now, settings.userId, settings.destination, claimedDueAt],
    });
    if (claimed.rowsAffected !== 1) continue;
    settings.nextDueAt = nextDueAt;
    settings.lastAttemptAt = now;
    try {
      await deliverScheduledAnalyticsPdf(env, db, settings);
    } catch (error) {
      console.error('Scheduled Analytics report delivery failed', {
        userId: settings.userId,
        destination: settings.destination,
        error: safeExternalUploadError(error),
      });
    }
  }
}

async function deliverScheduledAnalyticsPdf(env: Env, db: Client, settings: AnalyticsPdfScheduleSettings): Promise<void> {
  const attemptedAt = Date.now();
  try {
    const generated = await buildScheduledAnalyticsPdf(db, settings.userId, settings, attemptedAt);
    if (settings.destination === 'telegram') {
      const telegram = await readTelegramBackupSettings(db, settings.userId);
      if (!telegram.encryptedToken || !telegram.chatId) throw new HttpError(400, 'Telegram credentials are incomplete. Configure them in Settings > Credential.');
      const token = await decryptTelegramBotToken(env.JWT_SECRET, telegram.encryptedToken, telegram.tokenIv);
      await sendTelegramAnalyticsDocument(token, telegram.chatId, generated.fileName, generated.bytes, generated.caption, generated.mimeType);
    } else {
      const drive = await readGoogleDriveAnalyticsSettings(db, settings.userId);
      if (!drive.connected) throw new HttpError(400, 'Google Drive is no longer connected.');
      const accessToken = await googleDriveAccessToken(env, drive);
      const folder = await resolveGoogleAnalyticsFolder(accessToken, drive.folderId);
      await googleDriveUploadDocument(accessToken, folder.id, generated.fileName, generated.bytes, generated.mimeType);
      await db.execute({
        sql: 'UPDATE analytics_upload_settings SET google_last_upload_at = ?, google_last_error = NULL, updated_at = ? WHERE user_id = ?',
        args: [Date.now(), Date.now(), settings.userId],
      });
    }
    const sentAt = Date.now();
    await db.execute({
      sql: `UPDATE analytics_pdf_schedules
            SET last_sent_at = ?, last_attempt_at = ?, last_error = NULL, updated_at = ?
            WHERE user_id = ? AND destination = ?`,
      args: [sentAt, attemptedAt, sentAt, settings.userId, settings.destination],
    });
  } catch (error) {
    const message = safeExternalUploadError(error);
    const failedAt = Date.now();
    if (settings.destination === 'googleDrive' && error instanceof HttpError && error.status === 401) {
      await db.batch([
        {
          sql: `UPDATE analytics_upload_settings
                SET google_refresh_token_encrypted = NULL, google_refresh_token_iv = NULL,
                    google_account_email = '', google_connected_at = NULL, google_last_error = ?, updated_at = ?
                WHERE user_id = ?`,
          args: [message, failedAt, settings.userId],
        },
        {
          sql: `UPDATE analytics_pdf_schedules
                SET enabled = 0, next_due_at = NULL, last_attempt_at = ?, last_error = ?, updated_at = ?
                WHERE user_id = ? AND destination = 'googleDrive'`,
          args: [attemptedAt, message, failedAt, settings.userId],
        },
        {
          sql: `UPDATE google_drive_backup_settings
                SET enabled = 0, next_due_at = NULL, last_error = ?, updated_at = ?
                WHERE user_id = ?`,
          args: [message, failedAt, settings.userId],
        },
      ], 'write');
    } else {
      await db.execute({
        sql: `UPDATE analytics_pdf_schedules
              SET last_attempt_at = ?, last_error = ?, updated_at = ?
              WHERE user_id = ? AND destination = ?`,
        args: [attemptedAt, message, failedAt, settings.userId, settings.destination],
      });
    }
    if (error instanceof HttpError) throw error;
    throw new HttpError(502, message);
  }
}

type ScheduledAnalyticsRange = { startMs: number | null; endMs: number | null; label: string; stamp: string; dayCount: number };

function scheduledAnalyticsRange(
  filter: AnalyticsPdfDateFilter,
  nowMs: number,
  offsetMinutes: number,
  customStart: string | null = null,
  customEnd: string | null = null,
): ScheduledAnalyticsRange {
  const offsetMs = offsetMinutes * 60_000;
  const localNow = new Date(nowMs + offsetMs);
  const y = localNow.getUTCFullYear();
  const m = localNow.getUTCMonth();
  const d = localNow.getUTCDate();
  const localMidnightUtc = (year: number, month: number, day: number) => Date.UTC(year, month, day) - offsetMs;
  const fmt = (valueMs: number) => {
    const value = new Date(valueMs + offsetMs);
    return `${value.getUTCFullYear()}-${String(value.getUTCMonth() + 1).padStart(2, '0')}-${String(value.getUTCDate()).padStart(2, '0')}`;
  };
  if (filter === 'allTime') return { startMs: null, endMs: null, label: 'All time', stamp: 'all-time', dayCount: 1 };
  if (filter === 'custom') {
    if (!customStart || !customEnd) throw new HttpError(400, 'Automatic report custom range is incomplete.');
    const [sy, sm, sd] = customStart.split('-').map(Number);
    const [ey, em, ed] = customEnd.split('-').map(Number);
    const start = localMidnightUtc(sy, sm - 1, sd);
    const end = localMidnightUtc(ey, em - 1, ed + 1);
    if (end <= start) throw new HttpError(400, 'Automatic report custom range is invalid.');
    return {
      startMs: start,
      endMs: end,
      label: customStart === customEnd ? customStart : `${customStart} - ${customEnd}`,
      stamp: customStart === customEnd ? customStart : `${customStart}_to_${customEnd}`,
      dayCount: Math.max(1, Math.round((end - start) / 86_400_000)),
    };
  }
  if (filter === 'today') {
    const start = localMidnightUtc(y, m, d);
    const end = localMidnightUtc(y, m, d + 1);
    return { startMs: start, endMs: end, label: fmt(start), stamp: fmt(start), dayCount: 1 };
  }
  if (filter === 'thisWeek') {
    const jsDay = localNow.getUTCDay();
    const weekday = jsDay === 0 ? 7 : jsDay;
    const start = localMidnightUtc(y, m, d - (weekday - 1));
    const end = start + 7 * 86_400_000;
    return { startMs: start, endMs: end, label: `${fmt(start)} - ${fmt(end - 1)}`, stamp: `${fmt(start)}_week`, dayCount: 7 };
  }
  if (filter === 'thisMonth') {
    const start = localMidnightUtc(y, m, 1);
    const end = localMidnightUtc(y, m + 1, 1);
    return { startMs: start, endMs: end, label: `${y}-${String(m + 1).padStart(2, '0')}`, stamp: `${y}-${String(m + 1).padStart(2, '0')}`, dayCount: Math.max(1, Math.round((end - start) / 86_400_000)) };
  }
  const start = localMidnightUtc(y, 0, 1);
  const end = localMidnightUtc(y + 1, 0, 1);
  return { startMs: start, endMs: end, label: String(y), stamp: String(y), dayCount: Math.max(1, Math.round((end - start) / 86_400_000)) };
}

function rowNumber(row: Record<string, unknown>, key: string): number {
  const value = Number(row[key] ?? 0);
  return Number.isFinite(value) ? value : 0;
}

function rowTimestamp(row: Record<string, unknown>, key: string): number | null {
  const raw = row[key];
  if (raw == null || raw === '') return null;
  if (typeof raw === 'number' && Number.isFinite(raw)) return Math.trunc(raw);
  const parsedNumber = Number(raw);
  if (Number.isFinite(parsedNumber) && String(raw).trim() !== '') return Math.trunc(parsedNumber);
  const parsedDate = Date.parse(String(raw));
  return Number.isFinite(parsedDate) ? parsedDate : null;
}

function transactionEffectiveTimestamp(row: Record<string, unknown>): number {
  const created = rowTimestamp(row, 'created_on') ?? 0;
  const end = rowTimestamp(row, 'end_on');
  return end != null && end >= created ? end : created;
}

function scheduledRangeContains(range: ScheduledAnalyticsRange, valueMs: number): boolean {
  if (range.startMs == null || range.endMs == null) return true;
  return valueMs >= range.startMs && valueMs < range.endMs;
}

function scheduledAnalyticsMoney(currencyCode: string, value: number): string {
  const amount = Math.abs(value).toLocaleString('en-US', { maximumFractionDigits: 2 });
  return `${value < 0 ? '-' : ''}${currencyCode} ${amount}`;
}

function scheduledDateTimeLabel(valueMs: number, offsetMinutes: number): string {
  const date = new Date(valueMs + offsetMinutes * 60_000);
  return `${date.getUTCFullYear()}-${String(date.getUTCMonth() + 1).padStart(2, '0')}-${String(date.getUTCDate()).padStart(2, '0')} ${String(date.getUTCHours()).padStart(2, '0')}:${String(date.getUTCMinutes()).padStart(2, '0')}`;
}

function scheduledAnalyticsComparison(current: number, previous: number): string {
  if (Math.abs(previous) < 0.0001) return Math.abs(current) < 0.0001 ? 'No change' : 'New activity';
  const percent = ((current - previous) / Math.abs(previous)) * 100;
  return `${percent > 0 ? '+' : ''}${percent.toFixed(1)}%`;
}

function previousScheduledRange(range: ScheduledAnalyticsRange): ScheduledAnalyticsRange | null {
  if (range.startMs == null || range.endMs == null) return null;
  const duration = range.endMs - range.startMs;
  return { startMs: range.startMs - duration, endMs: range.startMs, label: 'Previous period', stamp: 'previous', dayCount: range.dayCount };
}

function scheduledAnalyticsFileName(settings: AnalyticsPdfScheduleSettings, range: ScheduledAnalyticsRange): string {
  const extension = settings.fileFormat;
  return settings.reportVariant === 'transactionHistory'
    ? `Koinly-Transaction-History-${range.stamp}.${extension}`
    : `Koinly-Analytics-${settings.dateFilter}-${range.stamp}.${extension}`;
}

async function buildScheduledAnalyticsPdf(
  db: Client,
  userId: string,
  settings: AnalyticsPdfScheduleSettings,
  nowMs: number,
): Promise<{ fileName: string; bytes: Uint8Array<ArrayBuffer>; caption: string; mimeType: string }> {
  const snapshot = await readCloudFinanceSnapshot(db, userId);
  if (snapshot.financeRecordCount === 0) {
    throw new HttpError(409, 'The cloud copy contains no finance data. Upload local changes before automatic Analytics reports can be generated.');
  }
  const range = scheduledAnalyticsRange(settings.dateFilter, nowMs, settings.timezoneOffsetMinutes, settings.customStart, settings.customEnd);
  const transactions = snapshot.database.transactions
    .filter(row => scheduledRangeContains(range, transactionEffectiveTimestamp(row)))
    .sort((a, b) => transactionEffectiveTimestamp(b) - transactionEffectiveTimestamp(a));
  const currencyCode = cleanText(snapshot.preferences.currencyCode, 12) || 'BDT';
  const categories = new Map(snapshot.database.categories.map(row => [String(row.id ?? ''), String(row.name ?? 'Uncategorized')]));
  const accounts = new Map(snapshot.database.accounts.map(row => [String(row.id ?? ''), row]));
  const accountName = (id: unknown) => String(accounts.get(String(id ?? ''))?.name ?? 'Unknown account');
  const categoryName = (id: unknown) => categories.get(String(id ?? '')) ?? 'Uncategorized';
  const lines: string[] = [];

  if (settings.reportVariant === 'transactionHistory') {
    let income = 0;
    let expense = 0;
    let transferVolume = 0;
    let transferCount = 0;
    for (const tx of transactions) {
      const amount = rowNumber(tx, 'amount');
      const excluded = Number(tx.exclude_from_reports ?? 0) === 1;
      if (!excluded && tx.type === 'income') income += amount;
      if (!excluded && tx.type === 'expense') expense += amount;
      if (tx.type === 'transfer') { transferVolume += amount; transferCount += 1; }
    }
    lines.push('Koinly Transaction History');
    lines.push(`${scheduledDateFilterLabel(settings.dateFilter)} | ${range.label}`);
    lines.push(`Generated ${scheduledDateTimeLabel(nowMs, settings.timezoneOffsetMinutes)}`);
    lines.push('');
    lines.push(`Transactions: ${transactions.length}`);
    lines.push(`Income: ${scheduledAnalyticsMoney(currencyCode, income)}`);
    lines.push(`Expense: ${scheduledAnalyticsMoney(currencyCode, expense)}`);
    lines.push(`Net cash flow: ${scheduledAnalyticsMoney(currencyCode, income - expense)}`);
    lines.push(`Transfers: ${transferCount} (${scheduledAnalyticsMoney(currencyCode, transferVolume)})`);
    lines.push('');
    if (transactions.length === 0) {
      lines.push('No transactions in this date filter.');
    } else {
      for (const tx of transactions) {
        const date = scheduledDateTimeLabel(transactionEffectiveTimestamp(tx), settings.timezoneOffsetMinutes);
        const type = String(tx.linked_entity_type ?? '').startsWith('loan') ? 'Loan' : String(tx.type ?? 'expense');
        const amount = rowNumber(tx, 'amount');
        const sign = tx.type === 'income' ? '+' : tx.type === 'expense' ? '-' : '';
        const title = cleanText(tx.title, 120) || categoryName(tx.category_id);
        const route = tx.type === 'transfer'
          ? `${accountName(tx.from_account_id)} -> ${accountName(tx.to_account_id)}`
          : accountName(tx.from_account_id);
        lines.push(`${date} | ${type} | ${sign}${scheduledAnalyticsMoney(currencyCode, amount)} | ${title}`);
        lines.push(`Category: ${categoryName(tx.category_id)} | Account: ${route}${Number(tx.exclude_from_reports ?? 0) === 1 ? ' | Excluded from reports' : ''}`);
        const notes = cleanText(tx.notes, 500);
        if (notes) lines.push(`Notes: ${notes}`);
        lines.push('');
      }
    }
  } else {
    const coreFor = (targetRange: ScheduledAnalyticsRange) => {
      const txs = snapshot.database.transactions.filter(row => scheduledRangeContains(targetRange, transactionEffectiveTimestamp(row)));
      let income = 0;
      let expense = 0;
      let transferVolume = 0;
      let transferCount = 0;
      let savingsIn = 0;
      let savingsOut = 0;
      const expenseCategories = new Map<string, number>();
      const incomeCategories = new Map<string, number>();
      for (const tx of txs) {
        const amount = rowNumber(tx, 'amount');
        const excluded = Number(tx.exclude_from_reports ?? 0) === 1;
        const categoryId = String(tx.category_id ?? '');
        if (!excluded && tx.type === 'income') {
          income += amount;
          incomeCategories.set(categoryId, (incomeCategories.get(categoryId) ?? 0) + amount);
        }
        if (!excluded && tx.type === 'expense') {
          expense += amount;
          expenseCategories.set(categoryId, (expenseCategories.get(categoryId) ?? 0) + amount);
        }
        if (tx.type === 'transfer') {
          transferVolume += amount;
          transferCount += 1;
          const fromSavings = accounts.get(String(tx.from_account_id ?? ''))?.type === 'savings';
          const toSavings = accounts.get(String(tx.to_account_id ?? ''))?.type === 'savings';
          if (!fromSavings && toSavings) savingsIn += amount;
          if (fromSavings && !toSavings) savingsOut += amount;
        }
      }
      return { txs, income, expense, transferVolume, transferCount, savingsIn, savingsOut, expenseCategories, incomeCategories };
    };
    const current = coreFor(range);
    const reportDayCount = settings.dateFilter === 'allTime' && current.txs.length > 0
      ? Math.max(1, Math.floor((nowMs - Math.min(...current.txs.map(transactionEffectiveTimestamp))) / 86_400_000) + 1)
      : range.dayCount;
    const previousRange = previousScheduledRange(range);
    const previous = previousRange ? coreFor(previousRange) : null;
    const loanStarts = snapshot.database.loans.filter(row => {
      const value = rowTimestamp(row, 'start_date');
      return value != null && scheduledRangeContains(range, value);
    }).length;
    const repayments = snapshot.database.loan_payments.filter(row => {
      const value = rowTimestamp(row, 'paid_on');
      return value != null && scheduledRangeContains(range, value);
    });
    const repaymentTotal = repayments.reduce((sum, row) => sum + rowNumber(row, 'amount'), 0);

    let budgetLimit = 0;
    let budgetSpent = 0;
    let budgetCount = 0;
    for (const budget of snapshot.database.budgets) {
      const selected = String(budget.selected_month ?? '');
      const match = /^(\d{4})-(\d{2})$/.exec(selected);
      if (!match) continue;
      const monthStart = Date.UTC(Number(match[1]), Number(match[2]) - 1, 1) - settings.timezoneOffsetMinutes * 60_000;
      const monthEndDate = new Date(Date.UTC(Number(match[1]), Number(match[2]), 1));
      const monthEnd = monthEndDate.getTime() - settings.timezoneOffsetMinutes * 60_000;
      const overlaps = range.startMs == null || range.endMs == null || (range.startMs < monthEnd && range.endMs > monthStart);
      if (!overlaps) continue;
      budgetCount += 1;
      budgetLimit += rowNumber(budget, 'amount');
      const budgetId = String(budget.id ?? '');
      const allowedAccounts = new Set(snapshot.database.budget_accounts.filter(row => String(row.budget_id ?? '') === budgetId).map(row => String(row.account_id ?? '')));
      const allowedCategories = new Set(snapshot.database.budget_categories.filter(row => String(row.budget_id ?? '') === budgetId).map(row => String(row.category_id ?? '')));
      const allAccounts = Number(budget.all_accounts_selected ?? 1) === 1;
      const allCategories = Number(budget.all_categories_selected ?? 1) === 1;
      for (const tx of current.txs) {
        const when = transactionEffectiveTimestamp(tx);
        if (when < monthStart || when >= monthEnd || tx.type !== 'expense' || Number(tx.exclude_from_reports ?? 0) === 1) continue;
        if (!allAccounts && !allowedAccounts.has(String(tx.from_account_id ?? ''))) continue;
        if (!allCategories && !allowedCategories.has(String(tx.category_id ?? ''))) continue;
        budgetSpent += rowNumber(tx, 'amount');
      }
    }

    lines.push('Koinly Analytics');
    lines.push(`${scheduledDateFilterLabel(settings.dateFilter)} summary | ${range.label}`);
    lines.push(`Generated ${scheduledDateTimeLabel(nowMs, settings.timezoneOffsetMinutes)}`);
    lines.push('');
    lines.push(`Income: ${scheduledAnalyticsMoney(currencyCode, current.income)}`);
    lines.push(`Expense: ${scheduledAnalyticsMoney(currencyCode, current.expense)}`);
    lines.push(`Net cash flow: ${scheduledAnalyticsMoney(currencyCode, current.income - current.expense)}`);
    lines.push(`Transactions: ${current.txs.length}`);
    lines.push(`Average income / day: ${scheduledAnalyticsMoney(currencyCode, current.income / Math.max(1, reportDayCount))}`);
    lines.push(`Average expense / day: ${scheduledAnalyticsMoney(currencyCode, current.expense / Math.max(1, reportDayCount))}`);
    if (previous) {
      lines.push('');
      lines.push('Compared with previous period');
      lines.push(`Income: ${scheduledAnalyticsComparison(current.income, previous.income)}`);
      lines.push(`Expense: ${scheduledAnalyticsComparison(current.expense, previous.expense)}`);
      lines.push(`Net cash flow: ${scheduledAnalyticsComparison(current.income - current.expense, previous.income - previous.expense)}`);
    }
    lines.push('');
    lines.push('Activity');
    lines.push(`Income transactions: ${current.txs.filter(tx => tx.type === 'income' && Number(tx.exclude_from_reports ?? 0) !== 1).length}`);
    lines.push(`Expense transactions: ${current.txs.filter(tx => tx.type === 'expense' && Number(tx.exclude_from_reports ?? 0) !== 1).length}`);
    lines.push(`Transfers: ${current.transferCount} (${scheduledAnalyticsMoney(currencyCode, current.transferVolume)})`);
    lines.push(`Savings in: ${scheduledAnalyticsMoney(currencyCode, current.savingsIn)}`);
    lines.push(`Savings out: ${scheduledAnalyticsMoney(currencyCode, current.savingsOut)}`);
    lines.push(`Loan records started: ${loanStarts}`);
    lines.push(`Repayments: ${repayments.length} (${scheduledAnalyticsMoney(currencyCode, repaymentTotal)})`);
    if (budgetCount > 0) {
      lines.push(`Relevant budgets: ${budgetCount}`);
      lines.push(`Budget spend: ${scheduledAnalyticsMoney(currencyCode, budgetSpent)} of ${scheduledAnalyticsMoney(currencyCode, budgetLimit)}`);
    }
    const appendTop = (title: string, totals: Map<string, number>, overall: number) => {
      lines.push('');
      lines.push(title);
      const entries = [...totals.entries()].sort((a, b) => b[1] - a[1]).slice(0, 8);
      if (entries.length === 0) { lines.push('No activity in this period.'); return; }
      for (const [categoryId, amount] of entries) {
        const share = overall <= 0 ? 0 : (amount / overall) * 100;
        lines.push(`${categoryName(categoryId)} | ${share.toFixed(1)}% | ${scheduledAnalyticsMoney(currencyCode, amount)}`);
      }
    };
    appendTop('Top expense categories', current.expenseCategories, current.expense);
    appendTop('Top income categories', current.incomeCategories, current.income);
    lines.push('');
    lines.push('Current account balances');
    lines.push('Account balances are a current snapshot, not historical balances for the selected period.');
    for (const account of snapshot.database.accounts) {
      lines.push(`${String(account.name ?? 'Account')}: ${scheduledAnalyticsMoney(currencyCode, rowNumber(account, 'amount'))}`);
    }
    lines.push('');
    lines.push('Transfers are not counted as income or expense. This automatic report is generated from the latest finance data synchronized to the Self-Hosted Worker.');
  }

  const bytes = settings.fileFormat === 'pdf'
    ? buildSimpleTextPdf(lines)
    : settings.fileFormat === 'xlsx'
      ? buildSimpleXlsxFromLines(lines, settings.reportVariant === 'transactionHistory' ? 'Transactions' : 'Summary')
      : ownedUtf8(`${lines.join('\n')}\n`);
  if (bytes.byteLength > analyticsReportMaxBytes) throw new HttpError(413, 'The generated Analytics report is too large to upload safely.');
  return {
    fileName: scheduledAnalyticsFileName(settings, range),
    bytes,
    mimeType: analyticsReportMimeType(settings.fileFormat),
    caption: settings.reportVariant === 'transactionHistory'
      ? `Koinly Transaction History • ${settings.fileFormat.toUpperCase()}\n${range.label}`
      : `Koinly ${scheduledDateFilterLabel(settings.dateFilter)} Analytics • ${settings.fileFormat.toUpperCase()}\n${range.label}`,
  };
}

function scheduledDateFilterLabel(filter: AnalyticsPdfDateFilter): string {
  return ({ today: 'Today', thisWeek: 'This Week', thisMonth: 'This Month', thisYear: 'This Year', allTime: 'All Time', custom: 'Custom Range' } as const)[filter];
}

function ownedUtf8(value: string): Uint8Array<ArrayBuffer> {
  const encoded = new TextEncoder().encode(value);
  const owned = new Uint8Array(new ArrayBuffer(encoded.byteLength));
  owned.set(encoded);
  return owned;
}

function xmlEscape(value: string): string {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;');
}

function xlsxColumnName(index: number): string {
  let value = index + 1;
  let result = '';
  while (value > 0) {
    value -= 1;
    result = String.fromCharCode(65 + (value % 26)) + result;
    value = Math.floor(value / 26);
  }
  return result;
}

function crc32(data: Uint8Array<ArrayBuffer>): number {
  let crc = 0xffffffff;
  for (const byte of data) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit += 1) {
      crc = (crc & 1) !== 0 ? ((crc >>> 1) ^ 0xedb88320) : (crc >>> 1);
    }
  }
  return (crc ^ 0xffffffff) >>> 0;
}

function zipU16(value: number): Uint8Array<ArrayBuffer> {
  const bytes = new Uint8Array(new ArrayBuffer(2));
  new DataView(bytes.buffer).setUint16(0, value, true);
  return bytes;
}

function zipU32(value: number): Uint8Array<ArrayBuffer> {
  const bytes = new Uint8Array(new ArrayBuffer(4));
  new DataView(bytes.buffer).setUint32(0, value >>> 0, true);
  return bytes;
}

function concatOwned(parts: Uint8Array<ArrayBuffer>[]): Uint8Array<ArrayBuffer> {
  const total = parts.reduce((sum, part) => sum + part.byteLength, 0);
  const output = new Uint8Array(new ArrayBuffer(total));
  let offset = 0;
  for (const part of parts) {
    output.set(part, offset);
    offset += part.byteLength;
  }
  return output;
}

function buildStoredZip(entries: Array<{ name: string; data: Uint8Array<ArrayBuffer> }>): Uint8Array<ArrayBuffer> {
  const locals: Uint8Array<ArrayBuffer>[] = [];
  const centrals: Uint8Array<ArrayBuffer>[] = [];
  let offset = 0;
  for (const entry of entries) {
    const name = ownedUtf8(entry.name);
    const checksum = crc32(entry.data);
    const local = concatOwned([
      zipU32(0x04034b50), zipU16(20), zipU16(0x0800), zipU16(0), zipU16(0), zipU16(0),
      zipU32(checksum), zipU32(entry.data.byteLength), zipU32(entry.data.byteLength),
      zipU16(name.byteLength), zipU16(0), name, entry.data,
    ]);
    locals.push(local);
    const central = concatOwned([
      zipU32(0x02014b50), zipU16(20), zipU16(20), zipU16(0x0800), zipU16(0), zipU16(0), zipU16(0),
      zipU32(checksum), zipU32(entry.data.byteLength), zipU32(entry.data.byteLength),
      zipU16(name.byteLength), zipU16(0), zipU16(0), zipU16(0), zipU16(0), zipU32(0), zipU32(offset), name,
    ]);
    centrals.push(central);
    offset += local.byteLength;
  }
  const centralDirectory = concatOwned(centrals);
  const end = concatOwned([
    zipU32(0x06054b50), zipU16(0), zipU16(0), zipU16(entries.length), zipU16(entries.length),
    zipU32(centralDirectory.byteLength), zipU32(offset), zipU16(0),
  ]);
  return concatOwned([...locals, centralDirectory, end]);
}

export function buildSimpleXlsxFromLines(sourceLines: string[], sheetName: string): Uint8Array<ArrayBuffer> {
  const safeSheetName = (sheetName.replace(/[\\/:*?\[\]]/g, ' ').trim() || 'Report').slice(0, 31);
  const rows = sourceLines.map(line => {
    if (!line) return [] as string[];
    if (line.includes(' | ')) return line.split(' | ');
    const split = line.indexOf(': ');
    if (split > 0) return [line.slice(0, split), line.slice(split + 2)];
    return [line];
  });
  const sheetXml = ['<?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>'];
  rows.forEach((row, rowIndex) => {
    const rowNumber = rowIndex + 1;
    sheetXml.push(`<row r="${rowNumber}">`);
    row.forEach((cell, columnIndex) => {
      const ref = `${xlsxColumnName(columnIndex)}${rowNumber}`;
      const style = rowIndex === 0 ? ' s="1"' : '';
      sheetXml.push(`<c r="${ref}"${style} t="inlineStr"><is><t xml:space="preserve">${xmlEscape(cell)}</t></is></c>`);
    });
    sheetXml.push('</row>');
  });
  sheetXml.push('</sheetData></worksheet>');

  return buildStoredZip([
    {
      name: '[Content_Types].xml',
      data: ownedUtf8('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>'),
    },
    {
      name: '_rels/.rels',
      data: ownedUtf8('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>'),
    },
    {
      name: 'xl/workbook.xml',
      data: ownedUtf8(`<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="${xmlEscape(safeSheetName)}" sheetId="1" r:id="rId1"/></sheets></workbook>`),
    },
    {
      name: 'xl/_rels/workbook.xml.rels',
      data: ownedUtf8('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>'),
    },
    {
      name: 'xl/styles.xml',
      data: ownedUtf8('<?xml version="1.0" encoding="UTF-8" standalone="yes"?><styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="2"><font><sz val="11"/><name val="Aptos"/></font><font><b/><sz val="11"/><name val="Aptos"/></font></fonts><fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills><borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/></cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>'),
    },
    { name: 'xl/worksheets/sheet1.xml', data: ownedUtf8(sheetXml.join('')) },
  ]);
}

function buildSimpleTextPdf(sourceLines: string[]): Uint8Array<ArrayBuffer> {
  const sanitize = (value: string) => value.replace(/[^\x20-\x7E]/g, '?');
  const escape = (value: string) => sanitize(value).replace(/\\/g, '\\\\').replace(/\(/g, '\\(').replace(/\)/g, '\\)');
  const wrap = (value: string, width = 92): string[] => {
    const clean = sanitize(value).trimEnd();
    if (!clean) return [''];
    const result: string[] = [];
    let remaining = clean;
    while (remaining.length > width) {
      let cut = remaining.lastIndexOf(' ', width);
      if (cut < Math.floor(width * 0.55)) cut = width;
      result.push(remaining.slice(0, cut).trimEnd());
      remaining = remaining.slice(cut).trimStart();
    }
    result.push(remaining);
    return result;
  };
  const lines = sourceLines.flatMap(line => wrap(String(line)));
  const pages: string[][] = [];
  for (let index = 0; index < lines.length; index += 47) pages.push(lines.slice(index, index + 47));
  if (pages.length === 0) pages.push(['Koinly']);

  const objects = new Map<number, string>();
  const pageIds: number[] = [];
  objects.set(1, '<< /Type /Catalog /Pages 2 0 R >>');
  objects.set(3, '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>');
  let nextId = 4;
  for (const pageLines of pages) {
    const pageId = nextId++;
    const contentId = nextId++;
    pageIds.push(pageId);
    const commands = ['BT', '/F1 10 Tf', '48 796 Td', '15 TL'];
    for (const line of pageLines) {
      commands.push(`(${escape(line)}) Tj`, 'T*');
    }
    commands.push('ET');
    const stream = `${commands.join('\n')}\n`;
    objects.set(pageId, `<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 3 0 R >> >> /Contents ${contentId} 0 R >>`);
    objects.set(contentId, `<< /Length ${new TextEncoder().encode(stream).byteLength} >>\nstream\n${stream}endstream`);
  }
  objects.set(2, `<< /Type /Pages /Count ${pageIds.length} /Kids [${pageIds.map(id => `${id} 0 R`).join(' ')}] >>`);

  const encoder = new TextEncoder();
  let pdf = '%PDF-1.4\n%Koinly\n';
  const offsets: number[] = [0];
  for (let id = 1; id < nextId; id += 1) {
    offsets[id] = encoder.encode(pdf).byteLength;
    pdf += `${id} 0 obj\n${objects.get(id) ?? '<< >>'}\nendobj\n`;
  }
  const xrefOffset = encoder.encode(pdf).byteLength;
  pdf += `xref\n0 ${nextId}\n0000000000 65535 f \n`;
  for (let id = 1; id < nextId; id += 1) {
    pdf += `${String(offsets[id]).padStart(10, '0')} 00000 n \n`;
  }
  pdf += `trailer\n<< /Size ${nextId} /Root 1 0 R >>\nstartxref\n${xrefOffset}\n%%EOF\n`;
  return new Uint8Array<ArrayBuffer>(encoder.encode(pdf).buffer as ArrayBuffer);
}

async function googleDriveAccessToken(env: Env, settings: GoogleDriveAnalyticsSettings): Promise<string> {
  if (!settings.clientId || !settings.encryptedClientSecret || !settings.encryptedRefreshToken) {
    throw new HttpError(400, 'Connect Google Drive in Settings > Credential first.');
  }
  const clientSecret = await decryptWorkerSecret(
    env.JWT_SECRET,
    'google-drive-client-secret',
    settings.encryptedClientSecret,
    settings.clientSecretIv,
    'The saved Google OAuth Client Secret cannot be decrypted. Re-enter it in Koinly.',
  );
  const refreshToken = await decryptWorkerSecret(
    env.JWT_SECRET,
    'google-drive-refresh-token',
    settings.encryptedRefreshToken,
    settings.refreshTokenIv,
    'The saved Google Drive authorization cannot be decrypted. Reconnect Google Drive.',
  );
  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      client_id: settings.clientId,
      client_secret: clientSecret,
      refresh_token: refreshToken,
      grant_type: 'refresh_token',
    }).toString(),
  });
  const data = parseJsonRecord(await response.text());
  if (!response.ok) {
    if (String(data.error ?? '') === 'invalid_grant') {
      throw new HttpError(401, 'Google Drive authorization is no longer valid. Reconnect Google Drive in Settings > Credential.');
    }
    throw new HttpError(502, googleOAuthFailure(response.status, data));
  }
  const accessToken = String(data.access_token ?? '').trim();
  if (!accessToken) throw new HttpError(502, 'Google did not return a Drive access token.');
  return accessToken;
}

async function resolveGoogleAnalyticsFolder(
  accessToken: string,
  configuredFolderId: string,
): Promise<{ id: string; name: string }> {
  const folderId = normalizeGoogleDriveFolderId(configuredFolderId);
  if (folderId) return googleDriveFolderById(accessToken, folderId);
  return ensureGoogleAnalyticsFolder(accessToken);
}

async function resolveGoogleBackupFolder(
  accessToken: string,
  configuredFolderId: string,
): Promise<{ id: string; name: string }> {
  const folderId = normalizeGoogleDriveFolderId(configuredFolderId);
  if (folderId) return googleDriveFolderById(accessToken, folderId);
  return ensureGoogleBackupFolder(accessToken);
}

async function googleDriveFolderById(accessToken: string, folderId: string): Promise<{ id: string; name: string }> {
  const url = new URL(`https://www.googleapis.com/drive/v3/files/${encodeURIComponent(folderId)}`);
  url.searchParams.set('fields', 'id,name,mimeType,trashed,capabilities(canAddChildren)');
  url.searchParams.set('supportsAllDrives', 'true');
  const response = await fetch(url, {
    headers: { authorization: `Bearer ${accessToken}`, accept: 'application/json' },
  });
  const data = parseJsonRecord(await response.text());
  if (!response.ok) {
    if (response.status === 404 || response.status === 403) {
      throw new HttpError(400, 'The Google Drive folder ID is not accessible. Check the ID, folder permission, then reconnect Google Drive.');
    }
    throw new HttpError(502, googleDriveApiFailure(response.status, data));
  }
  if (String(data.mimeType ?? '') !== 'application/vnd.google-apps.folder' || data.trashed === true) {
    throw new HttpError(400, 'The configured Google Drive Folder ID does not point to an active folder.');
  }
  const capabilities = data.capabilities;
  if (capabilities && typeof capabilities === 'object' && (capabilities as Record<string, unknown>).canAddChildren === false) {
    throw new HttpError(400, 'Koinly does not have permission to upload files into the configured Google Drive folder.');
  }
  return { id: String(data.id ?? folderId), name: cleanText(data.name, 240) || 'Google Drive folder' };
}

async function ensureGoogleAnalyticsFolder(accessToken: string): Promise<{ id: string; name: string }> {
  const query = `name = '${analyticsGoogleDriveFolderName}' and mimeType = 'application/vnd.google-apps.folder' and trashed = false`;
  const listUrl = new URL('https://www.googleapis.com/drive/v3/files');
  listUrl.searchParams.set('q', query);
  listUrl.searchParams.set('spaces', 'drive');
  listUrl.searchParams.set('fields', 'files(id,name)');
  listUrl.searchParams.set('pageSize', '10');
  const listResponse = await fetch(listUrl, {
    headers: { authorization: `Bearer ${accessToken}`, accept: 'application/json' },
  });
  const listData = parseJsonRecord(await listResponse.text());
  if (!listResponse.ok) throw new HttpError(502, googleDriveApiFailure(listResponse.status, listData));
  const files = Array.isArray(listData.files) ? listData.files : [];
  const first = files.find(item => item && typeof item === 'object' && String((item as Record<string, unknown>).id ?? '')) as Record<string, unknown> | undefined;
  if (first) return { id: String(first.id), name: cleanText(first.name, 240) || analyticsGoogleDriveFolderName };

  const createResponse = await fetch('https://www.googleapis.com/drive/v3/files?fields=id,name', {
    method: 'POST',
    headers: {
      authorization: `Bearer ${accessToken}`,
      'content-type': 'application/json; charset=UTF-8',
      accept: 'application/json',
    },
    body: JSON.stringify({ name: analyticsGoogleDriveFolderName, mimeType: 'application/vnd.google-apps.folder' }),
  });
  const createData = parseJsonRecord(await createResponse.text());
  if (!createResponse.ok) throw new HttpError(502, googleDriveApiFailure(createResponse.status, createData));
  const createdId = String(createData.id ?? '');
  if (!createdId) throw new HttpError(502, 'Google Drive did not return the Analytics folder ID.');
  return { id: createdId, name: cleanText(createData.name, 240) || analyticsGoogleDriveFolderName };
}

async function ensureGoogleBackupFolder(accessToken: string): Promise<{ id: string; name: string }> {
  const query = `name = '${backupGoogleDriveFolderName}' and mimeType = 'application/vnd.google-apps.folder' and trashed = false`;
  const listUrl = new URL('https://www.googleapis.com/drive/v3/files');
  listUrl.searchParams.set('q', query);
  listUrl.searchParams.set('spaces', 'drive');
  listUrl.searchParams.set('fields', 'files(id,name)');
  listUrl.searchParams.set('pageSize', '10');
  const listResponse = await fetch(listUrl, {
    headers: { authorization: `Bearer ${accessToken}`, accept: 'application/json' },
  });
  const listData = parseJsonRecord(await listResponse.text());
  if (!listResponse.ok) throw new HttpError(502, googleDriveApiFailure(listResponse.status, listData));
  const files = Array.isArray(listData.files) ? listData.files : [];
  const first = files.find(item => item && typeof item === 'object' && String((item as Record<string, unknown>).id ?? '')) as Record<string, unknown> | undefined;
  if (first) return { id: String(first.id), name: cleanText(first.name, 240) || backupGoogleDriveFolderName };

  const createResponse = await fetch('https://www.googleapis.com/drive/v3/files?fields=id,name', {
    method: 'POST',
    headers: {
      authorization: `Bearer ${accessToken}`,
      'content-type': 'application/json; charset=UTF-8',
      accept: 'application/json',
    },
    body: JSON.stringify({ name: backupGoogleDriveFolderName, mimeType: 'application/vnd.google-apps.folder' }),
  });
  const createData = parseJsonRecord(await createResponse.text());
  if (!createResponse.ok) throw new HttpError(502, googleDriveApiFailure(createResponse.status, createData));
  const createdId = String(createData.id ?? '');
  if (!createdId) throw new HttpError(502, 'Google Drive did not return the Backup folder ID.');
  return { id: createdId, name: cleanText(createData.name, 240) || backupGoogleDriveFolderName };
}

async function googleDriveUploadDocument(
  accessToken: string,
  folderId: string,
  fileName: string,
  bytes: Uint8Array<ArrayBuffer>,
  mimeType = analyticsReportMimeType(fileName),
): Promise<{ id: string; webViewLink: string }> {
  const boundary = `koinly_${crypto.randomUUID().replace(/-/g, '')}`;
  const metadata = JSON.stringify({ name: fileName, parents: [folderId], mimeType });
  const body = new Blob([
    `--${boundary}\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n${metadata}\r\n`,
    `--${boundary}\r\nContent-Type: ${mimeType}\r\n\r\n`,
    bytes,
    `\r\n--${boundary}--`,
  ]);
  const uploadUrl = new URL('https://www.googleapis.com/upload/drive/v3/files');
  uploadUrl.searchParams.set('uploadType', 'multipart');
  uploadUrl.searchParams.set('fields', 'id,name,webViewLink');
  uploadUrl.searchParams.set('supportsAllDrives', 'true');
  const response = await fetch(uploadUrl, {
    method: 'POST',
    headers: {
      authorization: `Bearer ${accessToken}`,
      'content-type': `multipart/related; boundary=${boundary}`,
      accept: 'application/json',
    },
    body,
  });
  const data = parseJsonRecord(await response.text());
  if (!response.ok) throw new HttpError(502, googleDriveApiFailure(response.status, data));
  const id = String(data.id ?? '');
  if (!id) throw new HttpError(502, 'Google Drive did not return an uploaded file ID.');
  return { id, webViewLink: String(data.webViewLink ?? '') };
}

function googleOAuthFailure(status: number, data: Record<string, unknown>): string {
  const description = cleanText(data.error_description, 200);
  const code = cleanText(data.error, 80);
  if (description) return `Google OAuth rejected the request: ${description}`;
  if (code) return `Google OAuth rejected the request: ${code}`;
  return `Google OAuth returned HTTP ${status}.`;
}

function googleDriveApiFailure(status: number, data: Record<string, unknown>): string {
  const error = data.error;
  if (error && typeof error === 'object') {
    const message = cleanText((error as Record<string, unknown>).message, 200);
    if (message) return `Google Drive rejected the upload: ${message}`;
  }
  return `Google Drive API returned HTTP ${status}.`;
}

function parseJsonRecord(value: string): Record<string, unknown> {
  try {
    const parsed = JSON.parse(value);
    return parsed && typeof parsed === 'object' && !Array.isArray(parsed) ? parsed as Record<string, unknown> : {};
  } catch {
    return {};
  }
}

function googleDriveCallbackPage(title: string, message: string, ok: boolean, status: number): Response {
  const accent = ok ? '#16c79a' : '#ef5350';
  const html = `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>${escapeHtml(title)}</title><style>body{margin:0;background:#0f1217;color:#f4f7f5;font:16px system-ui,-apple-system,Segoe UI,sans-serif;display:grid;min-height:100vh;place-items:center;padding:24px;box-sizing:border-box}.card{max-width:560px;background:#0b2119;border:1px solid #244438;border-radius:28px;padding:28px;box-shadow:0 24px 80px #0008}h1{margin:0 0 12px;font-size:28px}p{margin:0;color:#a9bbb3;line-height:1.55}.dot{width:54px;height:54px;border-radius:18px;background:${accent}22;color:${accent};display:grid;place-items:center;font-size:28px;margin-bottom:18px}</style></head><body><main class="card"><div class="dot">${ok ? '✓' : '!'}</div><h1>${escapeHtml(title)}</h1><p>${escapeHtml(message)}</p></main></body></html>`;
  return new Response(html, {
    status,
    headers: {
      'content-type': 'text/html; charset=utf-8',
      'cache-control': 'no-store',
      'x-content-type-options': 'nosniff',
      'referrer-policy': 'no-referrer',
      'content-security-policy': "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'",
    },
  });
}

function escapeHtml(value: string): string {
  return value.replace(/[&<>"']/g, character => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[character] ?? character));
}

function safeExternalUploadError(error: unknown): string {
  return (error instanceof Error ? error.message : String(error)).replace(/\s+/g, ' ').slice(0, 220);
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

export function nextScheduledUploadDueAt(
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

export function nextTelegramBackupDueAt(
  settings: Pick<TelegramBackupSettings, 'frequency' | 'hour' | 'minute' | 'weekday' | 'monthDay' | 'timezoneOffsetMinutes'>,
  afterMs: number,
): number {
  return nextScheduledUploadDueAt(settings, afterMs);
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

async function encryptWorkerSecret(secret: string, purpose: string, plaintext: string): Promise<{ ciphertext: string; iv: string }> {
  const key = await workerSecretEncryptionKey(secret, purpose, ['encrypt']);
  const iv = crypto.getRandomValues(new Uint8Array(new ArrayBuffer(12)));
  const encrypted = await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, key, enc.encode(plaintext));
  return { ciphertext: b64urlBytes(encrypted), iv: b64urlBytes(iv) };
}

async function decryptWorkerSecret(
  secret: string,
  purpose: string,
  ciphertext: string,
  encodedIv: string,
  failureMessage: string,
): Promise<string> {
  try {
    const key = await workerSecretEncryptionKey(secret, purpose, ['decrypt']);
    const decrypted = await crypto.subtle.decrypt(
      { name: 'AES-GCM', iv: bytesFromB64Url(encodedIv) },
      key,
      bytesFromB64Url(ciphertext),
    );
    return new TextDecoder().decode(decrypted);
  } catch {
    throw new HttpError(503, failureMessage);
  }
}

async function workerSecretEncryptionKey(secret: string, purpose: string, usages: KeyUsage[]): Promise<CryptoKey> {
  const material = await crypto.subtle.digest('SHA-256', enc.encode(`koinly-worker-secret:${purpose}:${secret}`));
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

function bytesFromBase64(value: string): Uint8Array<ArrayBuffer> {
  const raw = atob(value);
  const bytes = new Uint8Array(new ArrayBuffer(raw.length));
  for (let index = 0; index < raw.length; index += 1) bytes[index] = raw.charCodeAt(index);
  return bytes;
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
    workerVersion: env.KOINLY_WORKER_VERSION ?? 'legacy',
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
      deploymentRecovery: '/v1/deployment-recovery/profile',
      telegramBackup: '/v1/telegram-backup/*',
      analyticsUpload: '/v1/analytics-upload/*',
    },
  });
}

async function healthResponse(env: Env): Promise<Response> {
  const configured = isWorkerConfigured(env);
  if (!configured) {
    return json({
      ok: false,
      service: 'koinly-sync',
      workerVersion: env.KOINLY_WORKER_VERSION ?? 'legacy',
      configured: false,
      registrationMode: 'first-user',
      telegramBackupAvailable: true,
      googleDriveBackupAvailable: true,
      analyticsUploadAvailable: true,
      realtimeSyncAvailable: Boolean(env.SYNC_HUB),
      profileMediaSyncAvailable: true,
      deploymentRecoveryAvailable: false,
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
    let deploymentRecoveryAvailable = false;
    if (!missingTables.includes('worker_state')) {
      const recoveryState = await db.execute({
        sql: `SELECT value FROM worker_state WHERE key = 'deployment_recovery_ciphertext' LIMIT 1`,
        args: [],
      });
      deploymentRecoveryAvailable = Boolean(String(recoveryState.rows[0]?.value ?? '').trim());
    }
    return json({
      ok: schemaReady,
      service: 'koinly-sync',
      workerVersion: env.KOINLY_WORKER_VERSION ?? 'legacy',
      configured: true,
      registrationMode: 'first-user',
      telegramBackupAvailable: true,
      googleDriveBackupAvailable: true,
      analyticsUploadAvailable: true,
      realtimeSyncAvailable: Boolean(env.SYNC_HUB),
      profileMediaSyncAvailable: true,
      deploymentRecoveryAvailable,
      databaseReachable: true,
      schemaReady,
      missingTables,
    }, schemaReady ? 200 : 503);
  } catch (error) {
    return json({
      ok: false,
      service: 'koinly-sync',
      workerVersion: env.KOINLY_WORKER_VERSION ?? 'legacy',
      configured: true,
      registrationMode: 'first-user',
      telegramBackupAvailable: true,
      googleDriveBackupAvailable: true,
      analyticsUploadAvailable: true,
      realtimeSyncAvailable: Boolean(env.SYNC_HUB),
      profileMediaSyncAvailable: true,
      deploymentRecoveryAvailable: false,
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
  if (existing.has('analytics_upload_settings')) {
    const analyticsUploadColumns = new Set((await db.execute("PRAGMA table_info('analytics_upload_settings')")).rows.map(row => String(row.name)));
    if (!analyticsUploadColumns.has('google_folder_id')) missing.push('analytics_upload_settings.google_folder_id');
  }
  return missing;
}

function databaseErrorMessage(error: unknown): string {
  const message = error instanceof Error ? error.message : String(error);
  if (message.trim().length === 0) return 'Unknown database error.';
  return message.replace(/\s+/g, ' ').slice(0, 240);
}

export async function register(request: Request, env: Env, db: Client): Promise<Response> {
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
    const registrationState = (await transaction.execute({
      sql: 'SELECT value FROM worker_state WHERE key = ?',
      args: ['registration_closed'],
    })).rows[0];
    const registrationClosed = String(registrationState?.value ?? '') === '1';
    if (registrationClosed || userCount > 0) {
      if (env.ADMIN_USERNAME || env.ADMIN_PASSWORD_HASH) {
        throw new HttpError(403, 'Registration is managed by the Worker administrator at /profile.', 'REGISTRATION_MANAGED');
      }
      throw new HttpError(403, 'Self-hosted registration is closed. Sign in with the first account.');
    }
    await transaction.execute({
      sql: 'INSERT INTO users(id, username, password_hash, recovery_key_hash, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)',
      args: [userId, username, passwordHash, recoveryKeyHash, now, now],
    });
    await transaction.execute({
      sql: `INSERT OR IGNORE INTO worker_state(key, value) VALUES ('deployment_owner_user_id', ?)`,
      args: [userId],
    });
    await transaction.execute({
      sql: 'INSERT INTO devices(id, user_id, name, platform, created_at, last_seen_at) VALUES (?, ?, ?, ?, ?, ?)',
      args: [deviceId, userId, deviceName, platform, now, now],
    });
    await transaction.execute(`INSERT OR REPLACE INTO worker_state(key, value) VALUES ('registration_closed', '1')`);
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


async function deploymentRecoveryOwnerUserId(db: Client): Promise<string> {
  const owner = await db.execute({
    sql: `SELECT value FROM worker_state WHERE key = 'deployment_owner_user_id'`,
    args: [],
  });
  const configured = String(owner.rows[0]?.value ?? '').trim();
  if (configured) return configured;

  const firstUser = await db.execute({
    sql: `SELECT id FROM users ORDER BY created_at ASC, id ASC LIMIT 1`,
    args: [],
  });
  const userId = String(firstUser.rows[0]?.id ?? '').trim();
  if (!userId) throw new HttpError(404, 'No sync account exists yet.', 'DEPLOYMENT_RECOVERY_NO_OWNER');
  await db.execute({
    sql: `INSERT OR IGNORE INTO worker_state(key, value) VALUES ('deployment_owner_user_id', ?)`,
    args: [userId],
  });
  return userId;
}

async function requireDeploymentRecoveryOwner(db: Client, auth: AuthContext): Promise<void> {
  const ownerUserId = await deploymentRecoveryOwnerUserId(db);
  if (ownerUserId !== auth.userId) {
    throw new HttpError(
      403,
      'Deployment values can only be recovered by the first Koinly sync account.',
      'DEPLOYMENT_RECOVERY_OWNER_REQUIRED',
    );
  }
}

function deploymentRecoveryProfilePayload(raw: unknown): Record<string, string | number> {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) {
    throw new HttpError(400, 'Deployment recovery profile is missing.');
  }
  const source = raw as Record<string, unknown>;
  const value = (key: string, max = 4096): string => {
    const result = String(source[key] ?? '').trim();
    if (!result || result.length > max) throw new HttpError(400, `Invalid deployment recovery field: ${key}.`);
    return result;
  };
  const workerName = value('workerName', 63).toLowerCase();
  const cloudflareAccountId = value('cloudflareAccountId', 64);
  const cloudflareApiToken = value('cloudflareApiToken', 4096);
  const tursoDatabaseUrl = value('tursoDatabaseUrl', 2048);
  const tursoAuthToken = value('tursoAuthToken', 4096);
  const jwtSecret = value('jwtSecret', 1024);
  const adminUsername = value('adminUsername', 120).toLowerCase();
  const adminPasswordHash = value('adminPasswordHash', 256);
  const workerUrl = value('workerUrl', 2048);
  const workerVersion = value('workerVersion', 64);

  if (!/^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/.test(workerName)) {
    throw new HttpError(400, 'Invalid Worker name in the deployment recovery profile.');
  }
  if (!/^[A-Fa-f0-9]{32}$/.test(cloudflareAccountId)) {
    throw new HttpError(400, 'Invalid Cloudflare Account ID in the deployment recovery profile.');
  }
  if (!/^libsql:\/\/[A-Za-z0-9.-]+\.turso\.io\/?$/.test(tursoDatabaseUrl)) {
    throw new HttpError(400, 'Invalid Turso database URL in the deployment recovery profile.');
  }
  if (jwtSecret.length < 32) throw new HttpError(400, 'Invalid JWT secret in the deployment recovery profile.');
  if (!/^pbkdf2\$100000\$[A-Za-z0-9_-]+\$[A-Za-z0-9_-]+$/.test(adminPasswordHash)) {
    throw new HttpError(400, 'Invalid administrator password verifier in the deployment recovery profile.');
  }
  let parsedWorkerUrl: URL;
  try {
    parsedWorkerUrl = new URL(workerUrl);
  } catch {
    throw new HttpError(400, 'Invalid Worker URL in the deployment recovery profile.');
  }
  if (parsedWorkerUrl.protocol !== 'https:' || parsedWorkerUrl.username || parsedWorkerUrl.password ||
      parsedWorkerUrl.pathname !== '/' || parsedWorkerUrl.search || parsedWorkerUrl.hash) {
    throw new HttpError(400, 'Invalid Worker URL in the deployment recovery profile.');
  }

  return {
    version: 1,
    workerName,
    cloudflareAccountId,
    cloudflareApiToken,
    tursoDatabaseUrl,
    tursoAuthToken,
    jwtSecret,
    adminUsername,
    adminPasswordHash,
    workerUrl: workerUrl.replace(/\/+$/, ''),
    workerVersion,
  };
}

async function saveDeploymentRecoveryProfile(
  request: Request,
  db: Client,
  env: Env,
  auth: AuthContext,
): Promise<Response> {
  await requireDeploymentRecoveryOwner(db, auth);
  const body = await readJson(request);
  const profile = deploymentRecoveryProfilePayload(body.profile);
  const encrypted = await encryptWorkerSecret(
    env.JWT_SECRET,
    'deployment-recovery-v1',
    JSON.stringify(profile),
  );
  await db.batch(
    [
      {
        sql: `INSERT OR REPLACE INTO worker_state(key, value) VALUES ('deployment_recovery_ciphertext', ?)`,
        args: [encrypted.ciphertext],
      },
      {
        sql: `INSERT OR REPLACE INTO worker_state(key, value) VALUES ('deployment_recovery_iv', ?)`,
        args: [encrypted.iv],
      },
      {
        sql: `INSERT OR REPLACE INTO worker_state(key, value) VALUES ('deployment_recovery_updated_at', ?)`,
        args: [String(Date.now())],
      },
    ],
    'write',
  );
  return privateJson({ ok: true, saved: true });
}

async function deploymentRecoveryProfile(db: Client, env: Env, auth: AuthContext): Promise<Response> {
  await requireDeploymentRecoveryOwner(db, auth);
  const rows = await db.execute({
    sql: `SELECT key, value FROM worker_state
          WHERE key IN ('deployment_recovery_ciphertext', 'deployment_recovery_iv', 'deployment_recovery_updated_at')`,
    args: [],
  });
  const values = new Map<string, string>();
  for (const row of rows.rows) values.set(String(row.key), String(row.value));
  const ciphertext = values.get('deployment_recovery_ciphertext') ?? '';
  const iv = values.get('deployment_recovery_iv') ?? '';
  if (!ciphertext || !iv) {
    throw new HttpError(404, 'No deployment recovery profile has been saved yet.', 'DEPLOYMENT_RECOVERY_NOT_FOUND');
  }
  const plaintext = await decryptWorkerSecret(
    env.JWT_SECRET,
    'deployment-recovery-v1',
    ciphertext,
    iv,
    'The saved deployment recovery profile can no longer be decrypted. Redeploy once from a device that still has the deployment values.',
  );
  let decoded: unknown;
  try {
    decoded = JSON.parse(plaintext);
  } catch {
    throw new HttpError(503, 'The saved deployment recovery profile is damaged.');
  }
  return privateJson({
    profile: deploymentRecoveryProfilePayload(decoded),
    updatedAt: Number(values.get('deployment_recovery_updated_at') ?? 0),
  });
}

async function deleteDeploymentRecoveryProfile(db: Client, auth: AuthContext): Promise<Response> {
  await requireDeploymentRecoveryOwner(db, auth);
  await db.batch(
    [
      { sql: `DELETE FROM worker_state WHERE key = 'deployment_recovery_ciphertext'`, args: [] },
      { sql: `DELETE FROM worker_state WHERE key = 'deployment_recovery_iv'`, args: [] },
      { sql: `DELETE FROM worker_state WHERE key = 'deployment_recovery_updated_at'`, args: [] },
    ],
    'write',
  );
  return privateJson({ ok: true, deleted: true });
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
  constructor(readonly status: number, message: string, readonly code?: string) {
    super(message);
  }
}
