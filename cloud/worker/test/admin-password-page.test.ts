import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import test from 'node:test';
import { verifyPassword } from '../src/index.ts';

test('browser setup generates compatible hashes, clears passwords, and rejects invalid input', async () => {
  const html = fs.readFileSync(new URL('../admin-password.html', import.meta.url), 'utf8');
  const script = html.match(/<script>([\s\S]+)<\/script>/)![1];
  let submit: (event: { preventDefault(): void }) => Promise<void>;
  const elements = Object.fromEntries(['setup', 'password', 'confirm', 'generate', 'message', 'result', 'hash'].map(id => [id, {
    value: '', textContent: '', hidden: false, disabled: false, focus() {}, select() {},
    addEventListener(_name: string, callback: typeof submit) { submit = callback; },
  }]));
  vm.runInNewContext(script, { document: { getElementById: (id: string) => elements[id] }, crypto, TextEncoder, Uint8Array, btoa });
  const run = async (password: string, confirmation = password) => {
    elements.password.value = password; elements.confirm.value = confirmation;
    await submit!({ preventDefault() {} });
  };
  await run('short'); assert.equal(elements.result.hidden, true);
  await run('a'.repeat(257)); assert.equal(elements.result.hidden, true);
  await run('local-test-password', 'different-password'); assert.match(elements.message.textContent, /do not match/);
  await run('local-test-password');
  const first = elements.hash.value;
  assert.equal(await verifyPassword('local-test-password', first), true);
  assert.equal(await verifyPassword('incorrect', first), false);
  assert.equal(elements.password.value, ''); assert.equal(elements.confirm.value, '');
  assert.equal(elements.result.hidden, false); assert.equal(elements.generate.disabled, false);
  await run('local-test-password'); assert.notEqual(elements.hash.value, first);
  assert.match(html, /connect-src 'none'; form-action 'none'/);
  assert.doesNotMatch(script, /fetch\(|XMLHttpRequest|localStorage|sessionStorage/);
});
