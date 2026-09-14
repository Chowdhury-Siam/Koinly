import { cp, mkdir, readdir, rm, stat } from 'node:fs/promises';
import { spawnSync } from 'node:child_process';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptDir = dirname(fileURLToPath(import.meta.url));
const workerDir = dirname(scriptDir);
const repoDir = dirname(dirname(workerDir));
const outputDir = join(workerDir, '.app-deploy-bundle');
const targetDir = join(repoDir, 'assets', 'worker');
const target = join(targetDir, 'koinly_sync_worker.js');

await rm(outputDir, { recursive: true, force: true });
await mkdir(outputDir, { recursive: true });
await mkdir(targetDir, { recursive: true });

const wrangler = process.platform === 'win32'
  ? join(workerDir, 'node_modules', '.bin', 'wrangler.cmd')
  : join(workerDir, 'node_modules', '.bin', 'wrangler');

const result = spawnSync(
  wrangler,
  [
    'deploy',
    '--dry-run',
    '--config',
    'wrangler.self-hosted.toml',
    '--name',
    'koinly-sync-worker',
    '--outdir',
    outputDir,
  ],
  {
    cwd: workerDir,
    stdio: 'inherit',
    env: { ...process.env, WRANGLER_SEND_METRICS: 'false' },
  },
);

if (result.status !== 0) {
  throw new Error(`Wrangler dry-run bundling failed with exit code ${result.status ?? 'unknown'}.`);
}

const files = await readdir(outputDir, { recursive: true });
const candidates = [];
for (const relative of files) {
  if (!relative.endsWith('.js') && !relative.endsWith('.mjs')) continue;
  const path = resolve(outputDir, relative);
  const info = await stat(path);
  if (info.isFile()) candidates.push({ path, size: info.size });
}

candidates.sort((a, b) => b.size - a.size);
if (candidates.length === 0 || candidates[0].size < 10000) {
  throw new Error('Wrangler did not produce a deployable JavaScript Worker bundle.');
}

await cp(candidates[0].path, target);
console.log(`Prepared app Worker bundle: ${target} (${candidates[0].size} bytes)`);
