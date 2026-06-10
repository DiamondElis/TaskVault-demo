import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { runner } from 'node-pg-migrate';
import './load-env.js';
import { getDatabaseUrl } from './index.js';

const migrationsDir = path.join(
  path.dirname(fileURLToPath(import.meta.url)),
  '../../migrations',
);

export async function runMigrations(direction: 'up' | 'down'): Promise<void> {
  await runner({
    databaseUrl: getDatabaseUrl(),
    dir: migrationsDir,
    direction,
    migrationsTable: 'pgmigrations',
    log: console.log,
  });
}

export async function runMigrationsUp(): Promise<void> {
  await runMigrations('up');
}
