/**
 * Demo seed orchestrator (M10 / T158–T159).
 *
 * Targets:
 *   SEED_TARGET=local  — docker-compose Postgres + LocalStack (default)
 *   SEED_TARGET=eks    — run seed Job on taskvault-eks via kubectl
 */
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const backendDir = path.join(repoRoot, 'backend');
const target = process.env.SEED_TARGET ?? 'local';

function run(command: string, args: string[], cwd: string, env?: NodeJS.ProcessEnv): void {
  const result = spawnSync(command, args, {
    cwd,
    stdio: 'inherit',
    env: { ...process.env, ...env },
  });

  if (result.status !== 0) {
    process.exit(result.status ?? 1);
  }
}

function ensureBackendDeps(): void {
  if (!fs.existsSync(path.join(backendDir, 'node_modules'))) {
    run('npm', ['install'], backendDir);
  }
}

if (target === 'eks') {
  run('bash', [path.join(repoRoot, 'scripts', 'eks-seed-demo.sh')], repoRoot);
  process.exit(0);
}

ensureBackendDeps();

const compose = 'docker compose -f docker-compose.local.yml';
run('bash', ['-lc', `${compose} up -d postgres localstack`], repoRoot);
run('bash', ['-lc', 'until docker exec taskvault-postgres pg_isready -U demo -d taskvault >/dev/null 2>&1; do sleep 1; done'], repoRoot);
run(
  'bash',
  [
    '-lc',
    'until curl -sf http://localhost:4566/_localstack/health 2>/dev/null | grep -qE \'"s3": "(available|running)"\'; do sleep 2; done',
  ],
  repoRoot,
);

const localEnv: NodeJS.ProcessEnv = {
  DATABASE_URL: process.env.DATABASE_URL ?? 'postgres://demo:password@localhost:5432/taskvault',
  AWS_ENDPOINT: process.env.AWS_ENDPOINT ?? 'http://localhost:4566',
  AWS_REGION: process.env.AWS_REGION ?? 'us-east-1',
  AWS_ACCESS_KEY_ID: process.env.AWS_ACCESS_KEY_ID ?? 'test',
  AWS_SECRET_ACCESS_KEY: process.env.AWS_SECRET_ACCESS_KEY ?? 'test',
  S3_BUCKET: process.env.S3_BUCKET ?? 'taskvault-user-files',
  DEMO_ADMIN_EMAIL: process.env.DEMO_ADMIN_EMAIL ?? 'admin@taskvault.demo',
  DEMO_ADMIN_PASSWORD: process.env.DEMO_ADMIN_PASSWORD ?? 'password123',
};

// Local path: migrations (idempotent) + demo users/tasks/files/jobs + sensitive S3 fixtures.
run('npm', ['run', 'db:migrate'], backendDir, localEnv);
