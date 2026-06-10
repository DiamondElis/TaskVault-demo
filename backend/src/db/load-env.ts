import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import dotenv from 'dotenv';

const repoRoot = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  '../../..',
);

/** Load repo-root `.env` when present (local dev / make seed-demo). */
export function loadEnv(): void {
  const envFile = path.join(repoRoot, '.env');
  if (fs.existsSync(envFile)) {
    dotenv.config({ path: envFile });
  }
}

loadEnv();
