import { emitKeypressEvents } from 'node:readline';
import { hashPassword } from '../src/index.ts';

// Never put the password in shell arguments, environment files, or terminal output.
async function hiddenPassword(prompt) {
  if (!process.stdin.isTTY) throw new Error('Run this command in an interactive terminal.');
  process.stdout.write(prompt);
  emitKeypressEvents(process.stdin);
  process.stdin.setRawMode(true);
  process.stdin.resume();
  return new Promise((resolve, reject) => {
    let value = '';
    function finish(error) {
      process.stdin.off('keypress', keypress);
      process.stdin.setRawMode(false);
      process.stdin.pause();
      process.stdout.write('\n');
      if (error) reject(error); else resolve(value);
    }
    function keypress(text, key = {}) {
      if (key.ctrl && key.name === 'c') return finish(new Error('Cancelled.'));
      if (key.name === 'return' || key.name === 'enter') return finish();
      if (key.name === 'backspace') value = Array.from(value).slice(0, -1).join('');
      else if (!key.ctrl && !key.meta && text && !/[\x00-\x1f\x7f]/.test(text)) value += text;
    }
    process.stdin.on('keypress', keypress);
  });
}

try {
  const password = await hiddenPassword('Administrator password (12–256 characters; hidden): ');
  if (password.length < 12 || password.length > 256) throw new Error('Use a password with 12–256 characters.');
  if (password !== await hiddenPassword('Confirm password (hidden): ')) throw new Error('Passwords do not match.');
  console.log('\nSave this entire hash as the ADMIN_PASSWORD_HASH secret:');
  console.log(await hashPassword(password));
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}
