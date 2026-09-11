export function profileResponse(): Response {
  const nonce = crypto.randomUUID();
  return new Response(page.replaceAll('__NONCE__', nonce), { headers: {
    'content-type': 'text/html; charset=utf-8',
    'cache-control': 'no-store, private',
    'content-security-policy': `default-src 'none'; script-src 'nonce-${nonce}'; style-src 'nonce-${nonce}'; connect-src 'self'; img-src 'self' data:; base-uri 'none'; form-action 'self'; frame-ancestors 'none'`,
    'x-content-type-options': 'nosniff',
    'referrer-policy': 'no-referrer',
  } });
}

const page = String.raw`<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="dark light"><title>Profile · Koinly</title>
<style nonce="__NONCE__">
:root{font-family:system-ui,-apple-system,"Segoe UI",sans-serif;color:#e7f3ec;background:#06110d;--surface:#0b1914;--raised:#11251d;--line:#29463a;--muted:#8fa69c;--accent:#10b981;--danger:#ff7777}*{box-sizing:border-box}body{margin:0}main{max-width:1000px;margin:auto;padding:32px 24px}header,.row,.actions{display:flex;align-items:center;justify-content:space-between;gap:14px}.brand{font-size:24px;font-weight:750;letter-spacing:-1px}.mark{display:inline-grid;place-items:center;background:var(--accent);color:#06110d;width:42px;height:42px;border-radius:14px;margin-right:10px}h1{font-size:clamp(30px,5vw,42px);letter-spacing:-1.5px;margin:12px 0}h2{font-size:20px;margin:0 0 20px}p{color:var(--muted);line-height:1.6}section,.card,dialog{background:var(--surface);border:1px solid var(--line);border-radius:24px;padding:28px}#login{max-width:440px;margin:64px auto}.intro{margin:48px 0 28px}.eyebrow{color:var(--accent);font-size:13px;letter-spacing:2px;text-transform:uppercase}.stat{background:var(--raised);padding:20px 24px;border-radius:20px;margin-bottom:24px}.stat strong{font-size:36px;margin-right:12px}label{display:block;font-size:14px;margin:18px 0 8px}input,button{font:inherit}input{width:100%;padding:13px 15px;background:var(--raised);color:inherit;border:1px solid var(--line);border-radius:12px}button{cursor:pointer;padding:12px 18px;background:var(--accent);color:#042318;border:1px solid transparent;border-radius:999px;font-weight:650;min-height:44px}button.secondary{background:var(--raised);color:inherit;border-color:var(--line)}button.danger{background:transparent;color:var(--danger);border-color:var(--line)}button:disabled{opacity:.5;cursor:wait}button:focus-visible,input:focus-visible{outline:3px solid var(--accent);outline-offset:3px}.full{width:100%;margin-top:24px}.account{border-top:1px solid var(--line);padding:20px 0}.account:first-child{border-top:0}.account p{margin:5px 0 0;font-size:13px}.badge{display:inline-block;color:var(--accent);background:var(--raised);border-radius:30px;padding:4px 10px;margin-left:10px;font-size:12px}.actions{justify-content:flex-end;flex-wrap:wrap}#notice{white-space:pre-wrap;overflow-wrap:anywhere;color:inherit;background:var(--raised);border-radius:14px;padding:16px;margin-top:20px}#notice:empty{display:none}dialog{color:inherit;width:min(460px,calc(100% - 32px));max-height:90vh;overflow:auto}dialog::backdrop{background:#0009}dialog .actions{margin-top:24px}[hidden]{display:none!important}footer{color:var(--muted);font-size:12px;text-align:center;margin-top:32px}@media(max-width:600px){main{padding:20px 16px}section,.card,dialog{padding:20px}.account{align-items:flex-start;flex-direction:column}.account .actions{justify-content:flex-start}.intro{margin-top:32px}}@media(prefers-color-scheme:light){:root{color:#123b2b;background:#f6f9f6;--surface:#fff;--raised:#ecf4ef;--line:#b9cbc1;--muted:#526b5e;--danger:#b42323}}
</style></head><body><main>
<header><div class="brand"><span class="mark" aria-hidden="true">K</span>Koinly</div><button id="logout" class="secondary" hidden>Sign out</button></header>
<div id="notice" role="status" aria-live="polite"></div>
<section id="login"><span class="eyebrow">Your private space</span><h1>Welcome back</h1><p>Sign in with your Worker owner account to manage who can use your Koinly server.</p><form id="loginForm"><label for="username">Username</label><input id="username" name="username" autocomplete="username" required minlength="3" maxlength="32" autocapitalize="none" spellcheck="false"><label for="password">Password</label><input id="password" name="password" type="password" autocomplete="current-password" required><button class="full">Sign in</button></form></section>
<div id="dashboard" hidden><div class="intro"><span class="eyebrow">Profile</span><h1>Manage accounts</h1><p>One private server. Separate spaces for everyone.</p></div><div class="stat"><strong id="count">0</strong><span>total login accounts</span></div><section><div class="row"><h2>Accounts</h2><button id="add">+ Add account</button></div><p>Each login has its own finance data. The owner manages access.</p><div id="accounts"></div></section></div>
<dialog id="editor"><form id="editForm"><h2 id="editTitle"></h2><p id="editHelp"></p><div id="nameField"><label for="newUsername">Username</label><input id="newUsername" autocomplete="off" minlength="3" maxlength="32" pattern="[A-Za-z0-9_.-]{3,32}" autocapitalize="none"></div><div id="passwordField"><label for="newPassword">New password</label><input id="newPassword" type="password" autocomplete="new-password" minlength="8" maxlength="1024"><label for="repeatPassword">Confirm new password</label><input id="repeatPassword" type="password" autocomplete="new-password" minlength="8" maxlength="1024"></div><div id="confirmField"><label for="confirmUsername">Type the username to confirm</label><input id="confirmUsername" autocomplete="off"></div><label for="ownerPassword">Your current owner password</label><input id="ownerPassword" type="password" autocomplete="current-password" required><p id="editError" role="alert"></p><div class="actions"><button type="button" id="cancel" class="secondary">Cancel</button><button id="save">Save</button></div></form></dialog>
<footer>Koinly · Self-hosted account management</footer>
</main><script nonce="__NONCE__">
const $ = id => document.getElementById(id);
let session = null, ownerId = '', selected = null, action = '';
function signedOut() { session = null; $('editor').close(); $('editForm').reset(); $('password').value = ''; $('notice').textContent = ''; $('dashboard').hidden = true; $('logout').hidden = true; $('login').hidden = false; $('accounts').replaceChildren(); }
async function api(path, body) {
  const response = await fetch(path, {method:body ? 'POST':'GET', headers:{'content-type':'application/json', ...(session ? {authorization:'Bearer '+session.accessToken}:{})}, ...(body ? {body:JSON.stringify(body)}:{})});
  const data = await response.json();
  if (!response.ok) { if (response.status === 401 && session) signedOut(); throw new Error(data.error || 'Request failed. Please try again.'); }
  return data;
}
async function busy(form, task) { const buttons = form.querySelectorAll('button'); buttons.forEach(b => b.disabled = true); try { await task(); } finally { buttons.forEach(b => b.disabled = false); } }
async function load() {
  const data = await api('/v1/profile/accounts'); ownerId = data.ownerId; $('count').textContent = data.count; $('accounts').replaceChildren();
  for (const account of data.accounts) {
    const row = document.createElement('div'); row.className = 'account row';
    const info = document.createElement('div'); const name = document.createElement('strong'); name.textContent = account.username; info.append(name);
    if (account.id === ownerId) { const badge = document.createElement('span'); badge.className = 'badge'; badge.textContent = 'Owner'; info.append(badge); }
    const date = document.createElement('p'); date.textContent = 'Added '+new Date(Number(account.created_at)).toLocaleDateString(); info.append(date);
    const actions = document.createElement('div'); actions.className = 'actions';
    for (const kind of ['password','delete']) { if (kind === 'delete' && account.id === ownerId) continue; const button = document.createElement('button'); button.textContent = kind === 'password' ? 'Change password' : 'Delete'; button.className = kind === 'delete' ? 'danger' : 'secondary'; button.onclick = () => edit(kind,account); actions.append(button); }
    row.append(info,actions); $('accounts').append(row);
  }
  $('login').hidden = true; $('dashboard').hidden = false; $('logout').hidden = false;
}
$('loginForm').onsubmit = event => { event.preventDefault(); busy(event.target,async () => { try { $('notice').textContent = ''; session = await api('/v1/auth/login',{username:$('username').value,password:$('password').value,deviceId:crypto.randomUUID(),deviceName:'Profile browser',platform:'web'}); $('password').value = ''; await load(); } catch(error) { signedOut(); $('notice').textContent = error.message; } }); };
$('logout').onclick = async () => { try { await api('/v1/auth/logout',{refreshToken:session.refreshToken}); } catch {} finally { signedOut(); $('notice').textContent = 'Signed out.'; } };
function edit(kind, account = null) {
  action = kind; selected = account; $('editForm').reset(); $('editError').textContent = '';
  $('editTitle').textContent = kind === 'create' ? 'Add account' : kind === 'delete' ? 'Delete '+account.username+'?' : 'Change password';
  $('editHelp').textContent = kind === 'delete' ? 'This permanently deletes this login and all its cloud finance data and Telegram settings. Local device copies remain. This cannot be undone.' : 'Passwords must have at least 8 characters. Changing a password signs out existing sessions.';
  $('nameField').hidden = kind !== 'create'; $('newUsername').required = kind === 'create';
  $('passwordField').hidden = kind === 'delete'; $('newPassword').required = $('repeatPassword').required = kind !== 'delete';
  $('confirmField').hidden = kind !== 'delete'; $('confirmUsername').required = kind === 'delete';
  $('save').textContent = kind === 'delete' ? 'Delete permanently' : 'Save'; $('save').className = kind === 'delete' ? 'danger' : '';
  $('editor').showModal();
}
$('add').onclick = () => edit('create'); $('cancel').onclick = () => $('editor').close();
$('editor').onclose = () => $('editForm').reset();
$('editForm').onsubmit = event => { event.preventDefault(); busy(event.target,async () => { try {
  if (action !== 'delete' && $('newPassword').value !== $('repeatPassword').value) throw new Error('New passwords do not match.');
  const data = await api('/v1/profile/accounts',{action,id:selected?.id,username:$('newUsername').value,password:$('newPassword').value,currentPassword:$('ownerPassword').value,confirmUsername:$('confirmUsername').value});
  $('editor').close();
  if (action === 'password' && selected.id === ownerId) { signedOut(); $('notice').textContent = 'Password changed. Sign in with your new password.'; return; }
  $('notice').textContent = data.recoveryKey ? 'Account created. Save this recovery key now; it is shown only once:\n'+data.recoveryKey : action === 'delete' ? 'Account and cloud data deleted.' : 'Password changed. Existing sessions have been signed out.';
  await load();
} catch(error) { $(session ? 'editError' : 'notice').textContent = error.message; } }); };
</script></body></html>`;
