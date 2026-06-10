/**
 * Demo seed orchestrator: DB migrations now; S3 fixtures in a later milestone.
 * Invoked by `make seed-demo` via backend's tsx binary.
 */
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const backendDir = path.join(repoRoot, 'backend');

function run(command: string, args: string[], cwd: string): void {
  const result = spawnSync(command, args, {
    cwd,
    stdio: 'inherit',
    env: {
      ...process.env,
      DATABASE_URL: process.env.DATABASE_URL ?? 'postgres://demo:password@localhost:5432/taskvault',
    },
  });

  if (result.status !== 0) {
    process.exit(result.status ?? 1);
  }
}

if (!fs.existsSync(path.join(backendDir, 'node_modules'))) {
  run('npm', ['install'], backendDir);
}

run('npm', ['run', 'db:migrate'], backendDir);

// TODO: upload synthetic CSV fixtures to LocalStack S3 (uploads/sensitive/*)
