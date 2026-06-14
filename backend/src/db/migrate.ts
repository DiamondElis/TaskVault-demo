import path from 'node:path';
import { runner } from 'node-pg-migrate';
import './load-env.js';
import { getDatabaseUrl } from './index.js';

const migrationsDir = path.join(process.cwd(), 'migrations');

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
