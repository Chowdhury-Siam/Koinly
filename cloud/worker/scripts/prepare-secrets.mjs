import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';

function validateSecrets(env) {
  for (const name of ['TURSO_DATABASE_URL', 'TURSO_AUTH_TOKEN', 'JWT_SECRET']) {
    if (typeof env[name] !== 'string' || !env[name]) throw new Error(`Missing GitHub repository secret: ${name}.`);
  }
  if (env.JWT_SECRET.length < 32) throw new Error('JWT_SECRET must contain at least 32 characters.');
}

export async function deploymentSecrets(env) {
  validateSecrets(env);
  return {
    TURSO_DATABASE_URL: env.TURSO_DATABASE_URL,
    TURSO_AUTH_TOKEN: env.TURSO_AUTH_TOKEN,
    JWT_SECRET: env.JWT_SECRET,
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
