import assert from 'node:assert/strict';
import test from 'node:test';
import { profilePage } from '../src/profile.ts';

function passwordInputIds(html: string): string[] {
  return [...html.matchAll(/<input\b(?=[^>]*\btype="password")(?=[^>]*\bid="([^"]+)")[^>]*>/g)].map(match => match[1]);
}

test('every Worker website password field has an accessible visibility toggle', () => {
  for (const authenticated of [false, true]) {
    const html = profilePage(authenticated, 'test-nonce');
    const ids = passwordInputIds(html);
    assert.ok(ids.length > 0);

    for (const id of ids) {
      const escaped = id.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
      assert.match(
        html,
        new RegExp(`<button\\b[^>]*data-password-toggle[^>]*aria-controls="${escaped}"[^>]*aria-label="Show password"[^>]*aria-pressed="false"[^>]*>`),
      );
    }
  }
});

test('password toggles only change visibility and reset credential forms to hidden', () => {
  const html = profilePage(true, 'test-nonce');
  assert.match(html, /input\.type = visible \? 'text' : 'password'/);
  assert.match(html, /button\.setAttribute\('aria-label', visible \? 'Hide password' : 'Show password'\)/);
  assert.match(html, /resetPasswordVisibility\(editor\)/);
  assert.match(html, /resetPasswordVisibility\(form\)/);
});
