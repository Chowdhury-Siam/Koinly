import { createClient } from '@libsql/client/web';

const jsonHeaders = {
  'content-type': 'application/json; charset=utf-8',
  'access-control-allow-origin': '*',
  'access-control-allow-methods': 'GET,POST,OPTIONS',
  'access-control-allow-headers': 'content-type,authorization,x-admin-key',
};

const USER_STATUSES = new Set(['pending', 'approved', 'rejected', 'blocked']);

export default {
  async fetch(request, env) {
    if (request.method === 'OPTIONS') {
      return new Response(null, { headers: jsonHeaders });
    }

    const url = new URL(request.url);

    try {
      if (request.method === 'GET' && url.pathname === '/') {
        return json({ ok: true, service: 'koinly-sync', admin: `${url.origin}/admin` });
      }
      if (request.method === 'POST' && url.pathname === '/api/sync/push') {
        return await pushSnapshot(request, env);
      }
      if (request.method === 'POST' && url.pathname === '/api/sync/pull') {
        return await pullSnapshot(request, env);
      }
      if (request.method === 'GET' && url.pathname === '/api/admin/overview') {
        return await adminOverview(request, env);
      }
      if (request.method === 'POST' && url.pathname === '/api/admin/user-status') {
        return await adminSetUserStatus(request, env);
      }
      if (request.method === 'POST' && url.pathname === '/api/admin/delete') {
        return await adminDelete(request, env);
      }
      if (request.method === 'GET' && url.pathname === '/admin') {
        return new Response(adminHtml(), { headers: { 'content-type': 'text/html; charset=utf-8' } });
      }
      return json({ error: 'Not found' }, 404);
    } catch (error) {
      return json({ error: error?.message || 'Server error' }, 500);
    }
  },
};

function db(env) {
  if (!env.TURSO_DATABASE_URL || !env.TURSO_AUTH_TOKEN) {
    throw new Error('Missing TURSO_DATABASE_URL or TURSO_AUTH_TOKEN secret.');
  }
  return createClient({ url: env.TURSO_DATABASE_URL, authToken: env.TURSO_AUTH_TOKEN });
}

async function getDb(env) {
  const database = db(env);
  await ensureSchema(database);
  return database;
}

async function ensureSchema(database) {
  // Self-heals fresh Turso databases. The app no longer fails with
  // SQLITE_UNKNOWN/no such table when schema.sql was not run manually.
  await database.execute(`
    CREATE TABLE IF NOT EXISTS sync_snapshots (
      sync_id TEXT PRIMARY KEY,
      pin_hash TEXT NOT NULL,
      payload_json TEXT NOT NULL,
      payload_bytes INTEGER NOT NULL DEFAULT 0,
      device_id TEXT NOT NULL DEFAULT '',
      client_updated_at TEXT NOT NULL DEFAULT '',
      created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
      updated_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))
    )
  `);
  await database.execute(`
    CREATE INDEX IF NOT EXISTS idx_sync_snapshots_updated_at
      ON sync_snapshots(updated_at DESC)
  `);
  await database.execute(`
    CREATE TABLE IF NOT EXISTS sync_users (
      sync_id TEXT PRIMARY KEY,
      pin_hash TEXT NOT NULL DEFAULT '',
      status TEXT NOT NULL DEFAULT 'pending',
      device_id TEXT NOT NULL DEFAULT '',
      first_seen_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
      last_seen_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
      decided_at TEXT NOT NULL DEFAULT '',
      note TEXT NOT NULL DEFAULT ''
    )
  `);
  await database.execute(`
    CREATE INDEX IF NOT EXISTS idx_sync_users_status_seen
      ON sync_users(status, last_seen_at DESC)
  `);
  // Existing sync snapshots should continue working without a new approval.
  await database.execute(`
    INSERT OR IGNORE INTO sync_users(sync_id, pin_hash, status, device_id, first_seen_at, last_seen_at, decided_at, note)
    SELECT sync_id, pin_hash, 'approved', device_id, created_at, updated_at, updated_at, 'Migrated from existing sync snapshot.'
    FROM sync_snapshots
  `);
}

async function pushSnapshot(request, env) {
  const body = await readJson(request);
  const syncId = normalizeSyncId(body.syncId);
  const pin = String(body.pin || '').trim();
  const payload = body.payload;
  const deviceId = String(body.deviceId || '').slice(0, 120);
  const clientUpdatedAt = String(body.clientUpdatedAt || '').slice(0, 80);

  validateSync(syncId, pin);
  if (!payload || typeof payload !== 'object' || Array.isArray(payload)) {
    return json({ error: 'Missing sync payload.' }, 400);
  }

  const payloadJson = JSON.stringify(payload);
  const payloadBytes = new TextEncoder().encode(payloadJson).length;
  if (payloadBytes > 4_500_000) {
    return json({ error: 'Sync payload is too large for this starter backend.' }, 413);
  }

  const database = await getDb(env);
  const access = await requireApprovedSyncUser(database, env, { syncId, pin, deviceId });
  if (!access.ok) return access.response;

  const now = new Date().toISOString();
  await database.execute({
    sql: `INSERT INTO sync_snapshots(sync_id, pin_hash, payload_json, payload_bytes, device_id, client_updated_at, created_at, updated_at)
          VALUES(?, ?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT(sync_id) DO UPDATE SET
            pin_hash = excluded.pin_hash,
            payload_json = excluded.payload_json,
            payload_bytes = excluded.payload_bytes,
            device_id = excluded.device_id,
            client_updated_at = excluded.client_updated_at,
            updated_at = excluded.updated_at`,
    args: [syncId, access.pinHash, payloadJson, payloadBytes, deviceId, clientUpdatedAt, now, now],
  });

  return json({ ok: true, syncId, updatedAt: now, payloadBytes });
}

async function pullSnapshot(request, env) {
  const body = await readJson(request);
  const syncId = normalizeSyncId(body.syncId);
  const pin = String(body.pin || '').trim();
  const deviceId = String(body.deviceId || '').slice(0, 120);

  validateSync(syncId, pin);

  const database = await getDb(env);
  const access = await requireApprovedSyncUser(database, env, { syncId, pin, deviceId });
  if (!access.ok) return access.response;

  const result = await database.execute({
    sql: 'SELECT pin_hash, payload_json, updated_at, payload_bytes FROM sync_snapshots WHERE sync_id = ?',
    args: [syncId],
  });
  if (!result.rows.length) {
    return json({ error: 'No cloud data found for this Sync ID.' }, 404);
  }

  const row = result.rows[0];
  if (row.pin_hash !== access.pinHash) {
    return json({ error: 'Wrong Sync PIN.' }, 401);
  }

  return json({
    ok: true,
    syncId,
    updatedAt: row.updated_at,
    payloadBytes: row.payload_bytes,
    payload: JSON.parse(row.payload_json),
  });
}

async function requireApprovedSyncUser(database, env, { syncId, pin, deviceId }) {
  const pinHash = await hashPin(env, syncId, pin);
  const now = new Date().toISOString();

  const snapshot = await database.execute({ sql: 'SELECT pin_hash, device_id, created_at, updated_at FROM sync_snapshots WHERE sync_id = ?', args: [syncId] });
  if (snapshot.rows.length) {
    const snap = snapshot.rows[0];
    if (snap.pin_hash !== pinHash) {
      return { ok: false, response: json({ error: 'Wrong Sync PIN.' }, 401) };
    }
    await database.execute({
      sql: `INSERT INTO sync_users(sync_id, pin_hash, status, device_id, first_seen_at, last_seen_at, decided_at, note)
            VALUES(?, ?, 'approved', ?, ?, ?, ?, 'Existing cloud snapshot; approval kept automatically.')
            ON CONFLICT(sync_id) DO UPDATE SET
              pin_hash = excluded.pin_hash,
              status = CASE WHEN sync_users.status IN ('blocked','rejected') THEN sync_users.status ELSE 'approved' END,
              device_id = excluded.device_id,
              last_seen_at = excluded.last_seen_at,
              decided_at = CASE WHEN sync_users.decided_at = '' THEN excluded.decided_at ELSE sync_users.decided_at END`,
      args: [syncId, pinHash, deviceId || String(snap.device_id || ''), String(snap.created_at || now), now, now],
    });
    const refreshed = await database.execute({ sql: 'SELECT status FROM sync_users WHERE sync_id = ?', args: [syncId] });
    if (refreshed.rows[0]?.status === 'blocked') {
      return { ok: false, response: json({ code: 'SYNC_BLOCKED', error: 'Online sync is blocked for this Sync ID.' }, 403) };
    }
    if (refreshed.rows[0]?.status === 'rejected') {
      return { ok: false, response: json({ code: 'SYNC_REJECTED', error: 'Online sync was rejected for this Sync ID. Message admin if this is a mistake.' }, 403) };
    }
    return { ok: true, pinHash };
  }

  const users = await database.execute({ sql: 'SELECT pin_hash, status FROM sync_users WHERE sync_id = ?', args: [syncId] });
  if (!users.rows.length) {
    await database.execute({
      sql: `INSERT INTO sync_users(sync_id, pin_hash, status, device_id, first_seen_at, last_seen_at, note)
            VALUES(?, ?, 'pending', ?, ?, ?, 'Waiting for admin approval.')`,
      args: [syncId, pinHash, deviceId, now, now],
    });
    return approvalRequired(syncId);
  }

  const user = users.rows[0];
  if (user.pin_hash && user.pin_hash !== pinHash) {
    return { ok: false, response: json({ error: 'Wrong Sync PIN.' }, 401) };
  }
  await database.execute({
    sql: `UPDATE sync_users
          SET pin_hash = CASE WHEN pin_hash = '' THEN ? ELSE pin_hash END,
              device_id = ?,
              last_seen_at = ?
          WHERE sync_id = ?`,
    args: [pinHash, deviceId, now, syncId],
  });

  if (user.status === 'approved') {
    return { ok: true, pinHash };
  }
  if (user.status === 'blocked') {
    return { ok: false, response: json({ code: 'SYNC_BLOCKED', error: 'Online sync is blocked for this Sync ID.' }, 403) };
  }
  if (user.status === 'rejected') {
    return { ok: false, response: json({ code: 'SYNC_REJECTED', error: 'Online sync was rejected for this Sync ID. Message admin if this is a mistake.' }, 403) };
  }
  return approvalRequired(syncId);
}

function approvalRequired(syncId) {
  return {
    ok: false,
    response: json({
      code: 'SYNC_APPROVAL_REQUIRED',
      error: 'Message admin to activate your online sync.',
      syncId,
      telegramUrl: 'https://t.me/Ch0wdhury_Siam',
    }, 403),
  };
}

async function adminOverview(request, env) {
  if (!isAdmin(request, env)) return json({ error: 'Unauthorized.' }, 401);
  const database = await getDb(env);
  const result = await database.execute(`
    SELECT
      u.sync_id,
      u.status,
      u.device_id,
      u.first_seen_at,
      u.last_seen_at,
      u.decided_at,
      u.note,
      s.payload_bytes,
      s.client_updated_at,
      s.created_at AS snapshot_created_at,
      s.updated_at AS snapshot_updated_at
    FROM sync_users u
    LEFT JOIN sync_snapshots s ON s.sync_id = u.sync_id
    ORDER BY
      CASE u.status WHEN 'pending' THEN 0 WHEN 'approved' THEN 1 WHEN 'rejected' THEN 2 ELSE 3 END,
      u.last_seen_at DESC
    LIMIT 300
  `);
  return json({
    ok: true,
    total: result.rows.length,
    users: result.rows,
    snapshots: result.rows,
  });
}

async function adminSetUserStatus(request, env) {
  if (!isAdmin(request, env)) return json({ error: 'Unauthorized.' }, 401);
  const body = await readJson(request);
  const syncId = normalizeSyncId(body.syncId);
  const status = String(body.status || '').trim().toLowerCase();
  if (!syncId) return json({ error: 'Missing Sync ID.' }, 400);
  if (!USER_STATUSES.has(status)) return json({ error: 'Invalid status.' }, 400);
  const now = new Date().toISOString();
  await (await getDb(env)).execute({
    sql: `UPDATE sync_users SET status = ?, decided_at = ?, note = ? WHERE sync_id = ?`,
    args: [status, now, `Admin marked ${status}.`, syncId],
  });
  return json({ ok: true, syncId, status, decidedAt: now });
}

async function adminDelete(request, env) {
  if (!isAdmin(request, env)) return json({ error: 'Unauthorized.' }, 401);
  const body = await readJson(request);
  const syncId = normalizeSyncId(body.syncId);
  if (!syncId) return json({ error: 'Missing Sync ID.' }, 400);
  const database = await getDb(env);
  await database.execute({ sql: 'DELETE FROM sync_snapshots WHERE sync_id = ?', args: [syncId] });
  await database.execute({ sql: 'DELETE FROM sync_users WHERE sync_id = ?', args: [syncId] });
  return json({ ok: true });
}

function validateSync(syncId, pin) {
  if (syncId.length < 3) throw new Error('Sync ID must contain at least 3 letters or numbers.');
  if (pin.length < 4) throw new Error('Sync PIN must be at least 4 characters.');
}

async function hashPin(env, syncId, pin) {
  const secret = env.SYNC_SECRET || 'change-this-secret';
  const source = `${secret}::${syncId}::${pin}`;
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(source));
  return [...new Uint8Array(digest)].map((value) => value.toString(16).padStart(2, '0')).join('');
}

function normalizeSyncId(value) {
  return String(value || '')
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9_.-]/g, '-')
    .replace(/-+/g, '-')
    .slice(0, 80);
}

async function readJson(request) {
  try {
    return await request.json();
  } catch (_) {
    return {};
  }
}

function isAdmin(request, env) {
  const configured = env.ADMIN_KEY || '';
  if (!configured) return false;
  const auth = request.headers.get('authorization') || '';
  const bearer = auth.toLowerCase().startsWith('bearer ') ? auth.slice(7).trim() : '';
  const header = request.headers.get('x-admin-key') || '';
  return bearer === configured || header === configured;
}

function json(data, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: jsonHeaders });
}

function adminHtml() {
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width,initial-scale=1" />
  <title>Koinly Sync Admin</title>
  <style>
    :root { color-scheme: dark; font-family: Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
    body { margin: 0; background: #061012; color: #e7f5f7; }
    main { max-width: 1180px; margin: 0 auto; padding: 28px 16px; }
    .card { background: #10191d; border: 1px solid #1f3036; border-radius: 22px; padding: 18px; box-shadow: 0 18px 40px rgba(0,0,0,.22); margin-bottom: 16px; }
    h1 { margin: 0 0 6px; font-size: 28px; }
    h2 { margin: 0 0 12px; }
    p { color: #9fb2ba; }
    input, button { border-radius: 14px; border: 1px solid #2a4148; padding: 12px 14px; font: inherit; }
    input { background: #0b1518; color: #e7f5f7; width: min(100%, 380px); }
    button { background: #00c7d8; color: #041012; font-weight: 800; cursor: pointer; white-space: nowrap; }
    button.secondary { background: #1b2a2f; color: #e7f5f7; }
    button.danger { background: #ff5353; color: white; }
    button.warning { background: #f59e0b; color: #0b1518; }
    button.good { background: #27d17f; color: #061012; }
    table { width: 100%; border-collapse: collapse; min-width: 880px; }
    th, td { text-align: left; padding: 12px; border-bottom: 1px solid #21343a; vertical-align: top; }
    th { color: #9fb2ba; font-size: 13px; }
    .row { display: flex; gap: 10px; flex-wrap: wrap; align-items: center; }
    .hidden { display: none; }
    .status { display: inline-flex; padding: 5px 10px; border-radius: 999px; font-weight: 900; font-size: 12px; border: 1px solid #2a4148; }
    .pending { background: rgba(245,158,11,.16); color: #fbbf24; }
    .approved { background: rgba(39,209,127,.16); color: #34d399; }
    .rejected { background: rgba(255,83,83,.14); color: #ff8d8d; }
    .blocked { background: rgba(148,163,184,.14); color: #cbd5e1; }
    code { color: #78d8e8; }
    small { color: #9fb2ba; }
    .actions { display: flex; gap: 8px; flex-wrap: wrap; }
  </style>
</head>
<body>
<main>
  <section id="loginCard" class="card">
    <h1>Koinly Sync Admin</h1>
    <p>Login with your <code>ADMIN_KEY</code>. Sync information appears only after login.</p>
    <div class="row">
      <input id="key" type="password" placeholder="ADMIN_KEY" autocomplete="current-password" />
      <button id="loginButton">Login</button>
    </div>
    <p id="loginStatus"></p>
  </section>

  <section id="dashboard" class="hidden">
    <section class="card">
      <div class="row" style="justify-content:space-between">
        <div>
          <h1>Koinly Sync Admin</h1>
          <p>Approve, reject, or block Sync IDs. Finance payloads are not displayed.</p>
        </div>
        <div class="row">
          <button class="secondary" id="refreshButton">Refresh</button>
          <button class="danger" id="logoutButton">Logout</button>
        </div>
      </div>
    </section>
    <section class="card">
      <h2>Sync users</h2>
      <div id="status">Not loaded.</div>
      <div style="overflow:auto"><table id="table"></table></div>
    </section>
  </section>
</main>
<script>
const keyInput = document.getElementById('key');
const loginCard = document.getElementById('loginCard');
const dashboard = document.getElementById('dashboard');
const loginStatus = document.getElementById('loginStatus');
const table = document.getElementById('table');
const statusBox = document.getElementById('status');
keyInput.value = localStorage.getItem('koinly_admin_key') || '';

document.getElementById('loginButton').addEventListener('click', login);
document.getElementById('refreshButton').addEventListener('click', loadData);
document.getElementById('logoutButton').addEventListener('click', logout);
keyInput.addEventListener('keydown', function(event){ if(event.key === 'Enter') login(); });
if (keyInput.value) login();

async function login(){
  localStorage.setItem('koinly_admin_key', keyInput.value);
  loginStatus.textContent = 'Checking key...';
  try {
    await loadData();
    loginCard.classList.add('hidden');
    dashboard.classList.remove('hidden');
    loginStatus.textContent = '';
  } catch (e) {
    loginStatus.textContent = e.message;
    dashboard.classList.add('hidden');
  }
}

function logout(){
  localStorage.removeItem('koinly_admin_key');
  keyInput.value = '';
  table.innerHTML = '';
  statusBox.textContent = 'Not loaded.';
  dashboard.classList.add('hidden');
  loginCard.classList.remove('hidden');
}

async function api(path, options){
  const key = localStorage.getItem('koinly_admin_key') || keyInput.value;
  const res = await fetch(path, {
    ...(options || {}),
    headers: { 'content-type': 'application/json', 'x-admin-key': key, ...((options || {}).headers || {}) }
  });
  const data = await res.json().catch(function(){ return {}; });
  if(!res.ok) throw new Error(data.error || 'Request failed');
  return data;
}

function fmtBytes(n){
  n = Number(n || 0);
  if(n < 1024) return n + ' B';
  if(n < 1048576) return (n/1024).toFixed(1)+' KB';
  return (n/1048576).toFixed(2)+' MB';
}

async function loadData(){
  statusBox.textContent = 'Loading...';
  table.innerHTML = '';
  const data = await api('/api/admin/overview');
  const users = data.users || data.snapshots || [];
  statusBox.textContent = users.length + ' sync user(s) found.';
  renderTable(users);
}

function renderTable(users){
  table.innerHTML = '';
  const header = document.createElement('tr');
  ['Status','Sync ID','Size','Device','Last seen','Cloud updated','Actions'].forEach(function(text){
    const th = document.createElement('th');
    th.textContent = text;
    header.appendChild(th);
  });
  table.appendChild(header);
  users.forEach(function(user){
    const tr = document.createElement('tr');
    tr.appendChild(cell(statusBadge(user.status)));
    const idCell = document.createElement('td');
    const code = document.createElement('code');
    code.textContent = user.sync_id || '';
    idCell.appendChild(code);
    tr.appendChild(idCell);
    tr.appendChild(textCell(fmtBytes(user.payload_bytes)));
    tr.appendChild(textCell(user.device_id || ''));
    tr.appendChild(textCell(user.last_seen_at || ''));
    tr.appendChild(textCell(user.snapshot_updated_at || 'No snapshot yet'));
    tr.appendChild(cell(actionButtons(user)));
    table.appendChild(tr);
  });
}

function statusBadge(status){
  const span = document.createElement('span');
  span.className = 'status ' + (status || 'pending');
  span.textContent = status || 'pending';
  return span;
}

function actionButtons(user){
  const div = document.createElement('div');
  div.className = 'actions';
  div.appendChild(makeButton('Approve', 'good', function(){ setStatus(user.sync_id, 'approved'); }));
  div.appendChild(makeButton('Reject', 'warning', function(){ setStatus(user.sync_id, 'rejected'); }));
  div.appendChild(makeButton('Block', 'danger', function(){ setStatus(user.sync_id, 'blocked'); }));
  div.appendChild(makeButton('Delete', 'secondary', function(){ deleteUser(user.sync_id); }));
  return div;
}

function makeButton(label, className, onClick){
  const btn = document.createElement('button');
  btn.textContent = label;
  btn.className = className;
  btn.addEventListener('click', onClick);
  return btn;
}

function cell(child){
  const td = document.createElement('td');
  td.appendChild(child);
  return td;
}

function textCell(value){
  const td = document.createElement('td');
  td.textContent = String(value || '');
  return td;
}

async function setStatus(syncId, nextStatus){
  await api('/api/admin/user-status', { method:'POST', body: JSON.stringify({ syncId: syncId, status: nextStatus }) });
  await loadData();
}

async function deleteUser(syncId){
  if(!confirm('Delete sync user and snapshot ' + syncId + '?')) return;
  await api('/api/admin/delete', { method:'POST', body: JSON.stringify({ syncId: syncId }) });
  await loadData();
}
</script>
</body>
</html>`;
}
