// Self-contained Worker page: no CDN, framework, or client-side credentials.
export function profilePage(authenticated: boolean, nonce: string, error = ''): string {
  const escape = (value: string) => value.replace(/[&<>"']/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[char]!));
  const username = '<label>Username<input name="username" autocomplete="username" required minlength="3" maxlength="32" pattern="[a-zA-Z0-9][a-zA-Z0-9._\\-]{1,30}[a-zA-Z0-9]" autocapitalize="none" spellcheck="false" aria-describedby="username-help"></label><small id="username-help">3–32 characters. Letters, numbers, dots, dashes, or underscores; start and end with a letter or number.</small>';
  return `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><meta name="color-scheme" content="light dark"><meta name="robots" content="noindex,nofollow"><title>Koinly · Administration</title>
<style nonce="${nonce}">
:root{color-scheme:light;--bg:#f6f9f6;--surface:#fff;--raised:#f3f8f4;--line:#d9e7de;--text:#152b20;--muted:#526b5e;--accent:#10b981;--accent-ink:#006544;--danger:#b42338;--danger-bg:#fff1f3;--shadow:0 12px 38px #123e2010}
@media(prefers-color-scheme:dark){:root:not([data-theme=light]){color-scheme:dark;--bg:#06110d;--surface:#0b1914;--raised:#11251d;--line:#29463a;--text:#e6f2eb;--muted:#9ab3a5;--accent-ink:#5ce1b4;--danger:#ff93a4;--danger-bg:#311b23;--shadow:0 12px 38px #0002}}
:root[data-theme=dark]{color-scheme:dark;--bg:#06110d;--surface:#0b1914;--raised:#11251d;--line:#29463a;--text:#e6f2eb;--muted:#9ab3a5;--accent-ink:#5ce1b4;--danger:#ff93a4;--danger-bg:#311b23;--shadow:0 12px 38px #0002}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--text);font:15px/1.5 Roboto,system-ui,-apple-system,"Segoe UI",sans-serif;min-height:100vh}button,input,select{font:inherit}button,select{cursor:pointer}button,a,input,select{touch-action:manipulation}button{min-height:44px;border:1px solid var(--line);border-radius:14px;padding:10px 16px;background:var(--surface);color:var(--text);font-weight:650;transition:transform .12s,background .19s,box-shadow .19s}button:hover{background:var(--raised);box-shadow:0 3px 12px #123e2010}button:active{transform:scale(.97)}button:disabled{cursor:wait;opacity:.55}button.primary{background:var(--accent);border-color:var(--accent);color:#042b1d}button.primary:hover{background:#34d399}button.danger{color:var(--danger);border-color:var(--danger)}button.danger:hover{background:var(--danger-bg)}:focus-visible{outline:3px solid var(--accent-ink);outline-offset:3px}
header{border-bottom:1px solid var(--line);background:var(--surface)}.topbar{max-width:1160px;margin:auto;padding:20px 28px;display:flex;align-items:center;justify-content:space-between;gap:16px}.brand{display:flex;align-items:center;gap:12px}.mark{display:grid;place-items:center;background:var(--accent);color:#063b27;font-size:26px;font-weight:900;width:46px;height:46px;border-radius:16px}.brand strong{font-size:23px;letter-spacing:-.8px}.eyebrow{display:block;color:var(--muted);font-size:10px;font-weight:750;letter-spacing:1.8px;text-transform:uppercase}.tools,.actions{display:flex;align-items:center;gap:10px;flex-wrap:wrap}.theme-label{display:flex;align-items:center;gap:8px;font-size:13px;color:var(--muted)}select{min-height:44px;border:1px solid var(--line);border-radius:14px;background:var(--surface);color:var(--text);padding:8px}
main{max-width:1160px;margin:0 auto;padding:38px 28px 60px}.heading{display:flex;justify-content:space-between;align-items:center;gap:20px;margin-bottom:26px}h1{font-size:32px;letter-spacing:-1px;line-height:1.2;margin:0 0 8px;font-weight:850}h2{font-size:19px;letter-spacing:-.4px;margin:0 0 6px}p{margin:0;color:var(--muted)}.pill{display:inline-flex;align-items:center;gap:7px;background:var(--raised);color:var(--accent-ink);border:1px solid var(--line);padding:6px 11px;border-radius:999px;font-size:12px;font-weight:650;white-space:nowrap}.dot{width:6px;height:6px;background:currentColor;border-radius:50%}.card{background:var(--surface);border:1px solid var(--line);border-radius:24px;box-shadow:var(--shadow);overflow:hidden;animation:enter .3s cubic-bezier(.2,0,0,1)}.stats{display:grid;grid-template-columns:1fr 1.5fr;gap:20px;margin-bottom:24px}.stat{padding:25px 28px}.stat-label{color:var(--muted);font-size:13px;font-weight:600}.number{font-size:46px;line-height:1.3;letter-spacing:-2px;font-weight:850}.stat-note{font-size:13px}.info-card{display:flex;align-items:center;gap:20px}.icon{color:var(--accent-ink);background:var(--raised);padding:14px;border-radius:20px;display:grid;place-items:center}.icon svg{width:28px;height:28px}.card-top{padding:24px;display:flex;justify-content:space-between;align-items:center;gap:20px}.card-top p{font-size:13px}.table-wrap{overflow:auto}table{width:100%;border-collapse:collapse;text-align:left}th{color:var(--muted);font-size:11px;text-transform:uppercase;letter-spacing:1px;background:var(--raised);padding:13px 24px;font-weight:700}td{padding:18px 24px;border-top:1px solid var(--line)}td:last-child,th:last-child{text-align:right}.account{display:flex;align-items:center;gap:12px}.avatar{width:40px;height:40px;background:var(--raised);color:var(--accent-ink);border:1px solid var(--line);border-radius:14px;display:grid;place-items:center;font-weight:750;flex:none}.account strong{overflow-wrap:anywhere}.row-actions{display:flex;justify-content:flex-end;gap:8px}.row-actions button{font-size:13px;padding:8px 12px}.status-invited{color:var(--muted)}time{color:var(--muted);font-size:13px;white-space:nowrap}.pagination{padding:16px 24px;border-top:1px solid var(--line);display:flex;justify-content:space-between;align-items:center;gap:12px;color:var(--muted);font-size:13px}.empty{padding:45px 24px;text-align:center}.empty .icon{width:64px;margin:0 auto 16px}.empty p{margin:8px 0 20px}.footnote{font-size:12px;margin-top:18px}
.login{max-width:440px;margin:45px auto 0;padding:32px}.login .icon{width:60px;margin-bottom:22px}.login h1{font-size:27px}.login p{margin-bottom:24px}form{display:grid;gap:16px}label{display:grid;gap:7px;font-size:13px;font-weight:650}input{background:var(--raised);border:1px solid var(--line);border-radius:14px;color:var(--text);width:100%;min-height:48px;padding:12px 14px;font-size:16px;transition:border-color .19s}input:focus{border-color:var(--accent)}small{font-size:12px;color:var(--muted);margin-top:-10px}.login .primary{margin-top:6px}.login-footer{text-align:center;font-size:12px;margin-top:22px}.notice{padding:13px 16px;border:1px solid var(--line);border-radius:16px;background:var(--raised);color:var(--accent-ink);margin-bottom:22px;overflow-wrap:anywhere}.notice.error{background:var(--danger-bg);color:var(--danger);border-color:var(--danger)}[hidden]{display:none!important}dialog{max-width:460px;width:calc(100% - 32px);max-height:calc(100dvh - 40px);overflow:auto;background:var(--surface);color:var(--text);border:1px solid var(--line);border-radius:28px;padding:28px;box-shadow:var(--shadow)}dialog[open]{animation:enter .19s ease-out}dialog::backdrop{background:#02100ab3;backdrop-filter:blur(4px)}dialog p{margin:8px 0 24px;overflow-wrap:anywhere}dialog .actions{justify-content:flex-end;margin-top:8px}.dialog-name{color:var(--text);font-weight:700}.sr-only{position:absolute;width:1px;height:1px;padding:0;margin:-1px;overflow:hidden;clip:rect(0,0,0,0);white-space:nowrap;border:0}@keyframes enter{from{opacity:0;transform:translateY(8px)}to{opacity:1;transform:translateY(0)}}
@media(max-width:720px){.topbar{padding:16px;flex-wrap:wrap}.topbar .eyebrow{font-size:8px}.theme-label span{display:none}.tools{gap:6px}.tools button{padding:8px 10px}.brand{gap:8px}.mark{width:38px;height:38px;border-radius:13px}.brand strong{font-size:21px}main{padding:28px 16px 40px}.heading{align-items:flex-start;flex-direction:column;gap:14px}h1{font-size:28px}.stats{grid-template-columns:1fr;gap:14px}.stat{padding:22px}.card-top{padding:20px;flex-wrap:wrap;gap:16px}.card-top .actions{width:100%}.card-top .primary{flex:1}.login{margin-top:12px;padding:26px}.pagination{padding:16px;flex-wrap:wrap}thead{display:none}table,tbody,tr,td{display:block}tr{padding:18px 20px;border-top:1px solid var(--line);display:grid;grid-template-columns:1fr auto;gap:12px}td{padding:0;border:0}td:first-child{grid-column:1/-1}td:last-child{grid-column:1/-1}.row-actions{justify-content:stretch}.row-actions button{flex:1}td[data-label]::before{content:attr(data-label);display:block;font-size:10px;text-transform:uppercase;color:var(--muted);margin-bottom:5px}dialog{padding:24px}.info-card{gap:14px}}
@media(prefers-reduced-motion:reduce){*,*::before,*::after{animation:none!important;transition:none!important;scroll-behavior:auto!important}}
</style></head><body>
<header><div class="topbar"><div class="brand"><span class="mark" aria-hidden="true">K</span><div><strong>Koinly</strong><span class="eyebrow">Administration</span></div></div><div class="tools"><label class="theme-label"><span>Appearance</span><select id="theme" aria-label="Appearance"><option value="system">System</option><option value="light">Light</option><option value="dark">Dark</option></select></label>${authenticated ? '<button id="logout">Sign out</button>' : ''}</div></div></header>
<main><div id="notice" class="notice${error ? ' error' : ''}" role="status" aria-live="polite" ${error ? '' : 'hidden'}>${escape(error)}</div><noscript><p class="notice error">Enable JavaScript to use this administration portal.</p></noscript>
${authenticated ? `
<div id="dashboard"><div class="heading"><div><span class="eyebrow">Your self-hosted Worker</span><h1>Account overview</h1><p>A little control. Everything in one place.</p></div><span class="pill"><span class="dot"></span>Administrator session</span></div>
<div class="stats"><section class="card stat"><div class="stat-label">Registered accounts</div><div class="number" id="total" aria-live="polite">—</div><p class="stat-note">Accounts on this Worker</p></section><section class="card stat info-card"><span class="icon" aria-hidden="true">${shield}</span><div><h2>Your Worker, your people</h2><p>Create accounts and manage access.<br>Each account keeps its own synchronized data.</p></div></section></div>
<section class="card" aria-labelledby="accounts-title"><div class="card-top"><div><h2 id="accounts-title">Accounts</h2><p>Manage the people connected to your Worker.</p></div><div class="actions"><button id="refresh">Refresh</button><button id="create" class="primary">+ Create account</button></div></div><div id="loading" class="empty" role="status">Loading accounts…</div><div class="table-wrap" id="table-wrap" hidden><table><thead><tr><th>Username</th><th>Created</th><th>Status</th><th>Actions</th></tr></thead><tbody id="accounts"></tbody></table></div><div id="empty" class="empty" hidden><div class="icon" aria-hidden="true">${shield}</div><h2>No accounts yet</h2><p>Create the first account to get started.</p></div><div class="pagination"><span id="page-label">Loading…</span><div class="actions"><button id="previous" disabled>Previous</button><button id="next" disabled>Next</button></div></div></section><p class="footnote">Invited = has not signed in yet. Active = has signed in; this does not indicate who is online.</p></div>
<dialog id="editor" aria-labelledby="editor-title"><h2 id="editor-title">Create account</h2><p id="editor-description">Create a login for this Worker.</p><div id="editor-error" class="notice error" role="alert" hidden></div><form id="account-form"><div id="username-field">${username}</div><label>New password<input name="password" type="password" autocomplete="new-password" required minlength="8" maxlength="256" aria-describedby="password-help"></label><small id="password-help">Use 8–256 characters. Passwords are never shown in the account list.</small><label>Confirm password<input name="confirm" type="password" autocomplete="new-password" required minlength="8" maxlength="256"></label><div class="actions"><button type="button" data-close="editor">Cancel</button><button id="save" class="primary">Create account</button></div></form></dialog>
<dialog id="delete-dialog" aria-labelledby="delete-title"><h2 id="delete-title">Delete account?</h2><p>This permanently deletes <span class="dialog-name" id="delete-name"></span> and their synchronized cloud data, devices, and Telegram backup settings. Copies already stored on devices or sent to Telegram remain. This cannot be undone.</p><div id="delete-error" class="notice error" role="alert" hidden></div><div class="actions"><button data-close="delete-dialog" autofocus>Cancel</button><button id="confirm-delete" class="danger">Delete account</button></div></dialog>
<template id="account-row"><tr><td><div class="account"><span class="avatar" aria-hidden="true"></span><strong></strong></div></td><td data-label="Created"><time></time></td><td data-label="Status"><span class="pill"></span></td><td><div class="row-actions"><button data-action="password">Change password</button><button data-action="delete" class="danger">Delete</button></div></td></tr></template>
` : `
<section class="card login"><div class="icon" aria-hidden="true">${shield}</div><span class="eyebrow">Worker administration</span><h1>Welcome back</h1><p>Sign in with your Worker administrator credentials to manage accounts.</p><form id="login-form">${username}<label>Password<input name="password" type="password" autocomplete="current-password" required maxlength="256"></label><button class="primary" ${error ? 'disabled' : ''}>Sign in</button></form><div class="login-footer">A private space for your self-hosted Koinly.</div></section>`}
</main><script nonce="${nonce}">
const $ = id => document.getElementById(id);
const theme = $('theme');
try { theme.value = localStorage.getItem('koinly-profile-theme') || 'system'; } catch {}
function applyTheme() { document.documentElement.dataset.theme = theme.value; }
applyTheme();
theme.addEventListener('change', () => { applyTheme(); try { localStorage.setItem('koinly-profile-theme', theme.value); } catch {} });
function message(text, error = false, target = 'notice') { const box = $(target); box.textContent = text; box.classList.toggle('error', error); box.hidden = false; }
async function api(path, method = 'GET', body) {
  let response;
  try { response = await fetch('/profile/api/' + path, { method, credentials: 'same-origin', cache: 'no-store', headers: { 'content-type': 'application/json', 'x-profile-request': '1' }, body: body === undefined ? undefined : JSON.stringify(body) }); }
  catch { throw new Error('Could not reach the server. Check your connection and refresh to confirm the latest account state before retrying.'); }
  if (response.status === 401 && path !== 'login') { $('dashboard')?.remove(); document.querySelectorAll('dialog').forEach(dialog => dialog.close()); location.replace('/profile?expired=1'); throw new Error('Session expired. Sign in again.'); }
  let data;
  try { data = await response.json(); } catch { throw new Error('Server returned an unexpected response. Please try again.'); }
  if (!response.ok) throw new Error(data.error || 'Server/database error. Please try again.');
  return data;
}
async function busy(button, work) { if (button.disabled) return; button.disabled = true; button.setAttribute('aria-busy', 'true'); try { await work(); } finally { button.disabled = false; button.removeAttribute('aria-busy'); } }
window.addEventListener('pageshow', event => { if (event.persisted) location.reload(); });
const loginForm = $('login-form');
if (loginForm) {
  if (new URL(location.href).searchParams.has('expired')) message('Your session expired. Sign in again.', true);
  loginForm.addEventListener('submit', event => { event.preventDefault(); busy(loginForm.querySelector('button'), async () => { const data = new FormData(loginForm); const password = data.get('password'); loginForm.elements.password.value = ''; try { await api('login', 'POST', { username: data.get('username'), password }); location.replace('/profile'); } catch (error) { message(error.message, true); } }); });
} else {
  let page = 1, selected = null, total = 0, loading = false;
  const editor = $('editor'), form = $('account-form'), deletion = $('delete-dialog');
  async function load() {
    if (loading) return;
    loading = true; $('refresh').disabled = true; $('previous').disabled = true; $('next').disabled = true;
    try {
      let data = await api('accounts?page=' + page);
      const lastPage = Math.max(1, Math.ceil(data.total / data.pageSize));
      if (page > lastPage) { page = lastPage; data = await api('accounts?page=' + page); }
      total = data.total; $('total').textContent = String(total); $('accounts').replaceChildren();
      for (const account of data.accounts) {
        const row = $('account-row').content.cloneNode(true);
        row.querySelector('strong').textContent = account.username;
        row.querySelector('.avatar').textContent = account.username[0].toUpperCase();
        const time = row.querySelector('time'); time.dateTime = new Date(account.createdAt).toISOString(); time.textContent = new Date(account.createdAt).toLocaleDateString(undefined, { year: 'numeric', month: 'short', day: 'numeric' }); time.title = new Date(account.createdAt).toLocaleString();
        const status = row.querySelector('.pill'); status.textContent = account.status === 'active' ? 'Active' : 'Invited'; status.classList.toggle('status-invited', account.status !== 'active');
        for (const button of row.querySelectorAll('button')) { button.setAttribute('aria-label', button.textContent + ' for ' + account.username); button.addEventListener('click', () => button.dataset.action === 'delete' ? openDelete(account) : openEditor(account)); }
        $('accounts').append(row);
      }
      $('table-wrap').hidden = data.accounts.length === 0; $('empty').hidden = total !== 0; $('loading').hidden = true;
      $('page-label').textContent = total ? ((page - 1) * data.pageSize + 1) + '–' + Math.min(page * data.pageSize, total) + ' of ' + total + ' accounts' : '0 accounts';
    } catch (error) { message(error.message, true); $('loading').textContent = 'Unable to load accounts. Use Refresh to try again.'; }
    finally { loading = false; $('refresh').disabled = false; $('previous').disabled = page <= 1; $('next').disabled = page * 50 >= total; }
  }
  function openEditor(account = null) {
    selected = account; form.reset(); $('editor-error').hidden = true; $('username-field').hidden = Boolean(account); form.elements.username.disabled = Boolean(account);
    $('editor-title').textContent = account ? 'Change password' : 'Create account'; $('save').textContent = account ? 'Change password' : 'Create account';
    $('editor-description').textContent = account ? 'Set a new password for ' + account.username + '. This signs out their devices and invalidates their recovery key.' : 'Create a login for this Worker. Share the password privately with the account holder.';
    editor.showModal(); (account ? form.elements.password : form.elements.username).focus();
  }
  function openDelete(account) { selected = account; $('delete-name').textContent = account.username; $('delete-error').hidden = true; deletion.showModal(); }
  document.querySelectorAll('[data-close]').forEach(button => button.addEventListener('click', () => $(button.dataset.close).close()));
  [editor, deletion].forEach(dialog => dialog.addEventListener('cancel', event => { if (dialog.querySelector('[aria-busy=true]')) event.preventDefault(); }));
  editor.addEventListener('close', () => form.reset());
  $('create').addEventListener('click', () => openEditor()); $('refresh').addEventListener('click', load);
  $('previous').addEventListener('click', () => { page--; load(); }); $('next').addEventListener('click', () => { page++; load(); });
  form.addEventListener('submit', event => {
    event.preventDefault();
    if (form.elements.password.value !== form.elements.confirm.value) { message('Passwords do not match.', true, 'editor-error'); return; }
    busy($('save'), async () => {
      const data = new FormData(form); const account = selected; const cancel = editor.querySelector('[data-close]'); cancel.disabled = true;
      const password = data.get('password'); form.elements.password.value = ''; form.elements.confirm.value = '';
      try { const result = await api(account ? 'accounts/' + encodeURIComponent(account.id) + '/password' : 'accounts', 'POST', { username: data.get('username'), password }); editor.close(); message(result.message); if (!account) page = 1; await load(); }
      catch (error) { message(error.message, true, 'editor-error'); } finally { cancel.disabled = false; }
    });
  });
  $('confirm-delete').addEventListener('click', () => busy($('confirm-delete'), async () => {
    const cancel = deletion.querySelector('[data-close]'); cancel.disabled = true;
    try { const result = await api('accounts/' + encodeURIComponent(selected.id), 'DELETE'); deletion.close(); message(result.message); await load(); } catch (error) { message(error.message, true, 'delete-error'); } finally { cancel.disabled = false; }
  }));
  $('logout').addEventListener('click', () => busy($('logout'), async () => { try { await api('logout', 'POST', {}); $('dashboard').remove(); location.replace('/profile'); } catch (error) { message(error.message, true); } }));
  document.addEventListener('visibilitychange', () => { if (!document.hidden) load(); });
  load();
}
</script></body></html>`;
}

const shield = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><path d="m12 3 8 3v6c0 5-8 9-8 9s-8-4-8-9V6z"/><path d="m8 12 3 3 5-6"/></svg>';
