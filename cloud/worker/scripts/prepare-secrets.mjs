import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';
import { hashPassword } from '../src/index.ts';

function validateSecrets(env) {
  for (const name of ['TURSO_DATABASE_URL', 'TURSO_AUTH_TOKEN', 'JWT_SECRET', 'ADMIN_USERNAME', 'ADMIN_PASSWORD']) {
    if (typeof env[name] !== 'string' || !env[name]) throw new Error(`Missing GitHub repository secret: ${name}.`);
  }
  if (env.JWT_SECRET.length < 32) throw new Error('JWT_SECRET must contain at least 32 characters.');
  if (!/^[a-z0-9][a-z0-9._-]{1,30}[a-z0-9]$/.test(env.ADMIN_USERNAME)) {
    throw new Error('ADMIN_USERNAME must be 3–32 lowercase letters, numbers, dots, dashes, or underscores, starting and ending with a letter or number.');
  }
  if (env.ADMIN_PASSWORD.length < 12 || env.ADMIN_PASSWORD.length > 256) {
    throw new Error('ADMIN_PASSWORD must contain 12–256 characters.');
  }
}

export async function deploymentSecrets(env) {
  validateSecrets(env);
  // Only the salted verifier reaches Cloudflare; the original password stays in GitHub's encrypted secrets.
  return {
    TURSO_DATABASE_URL: env.TURSO_DATABASE_URL,
    TURSO_AUTH_TOKEN: env.TURSO_AUTH_TOKEN,
    JWT_SECRET: env.JWT_SECRET,
    ADMIN_USERNAME: env.ADMIN_USERNAME,
    ADMIN_PASSWORD_HASH: await hashPassword(env.ADMIN_PASSWORD),
  };
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    if (process.argv.includes('--check')) validateSecrets(process.env);
    else process.stdout.write(JSON.stringify(await deploymentSecrets(process.env)));
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
