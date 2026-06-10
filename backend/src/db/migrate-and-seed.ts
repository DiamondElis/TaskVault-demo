#!/usr/bin/env tsx
/**
 * Idempotent DB entrypoint for the db-migrator K8s Job and `make seed-demo`.
 * node-pg-migrate records applied revisions in `pgmigrations`, so repeated runs
 * only apply pending migrations.
 */
import { runMigrationsUp } from './migrate.js';

async function seedDemoData(): Promise<void> {
  // Demo row seeding is implemented in scripts/seed-demo-data.ts (later milestone).
}

async function main(): Promise<void> {
  console.log('Running database migrations...');
  await runMigrationsUp();
  console.log('Migrations complete.');

  console.log('Running demo seed (no-op until seed script is wired)...');
  await seedDemoData();
  console.log('Database ready.');
}

main().catch((error: unknown) => {
  console.error('migrate-and-seed failed:', error);
  process.exit(1);
});
