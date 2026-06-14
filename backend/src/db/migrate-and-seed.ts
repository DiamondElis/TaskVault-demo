#!/usr/bin/env tsx
/**
 * Idempotent DB entrypoint for the db-migrator K8s Job and `make seed-demo`.
 * node-pg-migrate records applied revisions in `pgmigrations`, so repeated runs
 * only apply pending migrations.
 */
import { resolveRuntimeSecrets } from '../aws/secrets.js';
import { getConfig, loadConfig } from '../config.js';
import { initPool } from './pool.js';
import { runMigrationsUp } from './migrate.js';
import { seedDemoData } from './seed-demo.js';

async function main(): Promise<void> {
  loadConfig();
  if (getConfig().inCluster) {
    await resolveRuntimeSecrets();
  }
  initPool(getConfig().databaseUrl);

  console.log('Running database migrations...');
  await runMigrationsUp();
  console.log('Migrations complete.');

  if (process.env.SKIP_DEMO_SEED === 'true') {
    console.log('Skipping demo seed (SKIP_DEMO_SEED=true).');
    return;
  }

  console.log('Running demo seed...');
  await seedDemoData();
  console.log('Database ready.');
}

main().catch((error: unknown) => {
  console.error('migrate-and-seed failed:', error);
  process.exit(1);
});
