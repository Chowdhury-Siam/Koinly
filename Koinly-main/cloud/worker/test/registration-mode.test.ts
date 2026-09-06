import assert from 'node:assert/strict';
import test from 'node:test';

import { registrationMode } from '../src/index.ts';

test('self-hosted deployments use first-user registration without managed invite secrets', () => {
  assert.equal(registrationMode({} as never), 'first-user');
  assert.equal(registrationMode({ TELEGRAM_BOT_TOKEN: 'bot' } as never), 'first-user');
  assert.equal(registrationMode({
    TELEGRAM_BOT_TOKEN: 'bot',
    REGISTRATION_KEY_CHAT_ID: 'chat',
    REGISTRATION_ADMIN_SECRET: 'a'.repeat(32),
  } as never), 'invite-key');
});
