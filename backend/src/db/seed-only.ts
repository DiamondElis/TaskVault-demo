#!/usr/bin/env tsx
/**
 * Demo seed entrypoint for `make seed-demo` and the EKS seed Job (M10).
 */
import { resolveRuntimeSecrets } from '../aws/secrets.js';
import { getConfig, loadConfig } from '../config.js';
import { initPool } from './pool.js';
import { seedDemoData } from './seed-demo.js';

async function main(): Promise<void> {
  loadConfig();
  if (getConfig().inCluster) {
    await resolveRuntimeSecrets();
  }
  initPool(getConfig().databaseUrl);

  console.log('Running demo seed...');
  await seedDemoData();
  console.log('Demo seed complete.');
}

main().catch((error: unknown) => {
  console.error('seed-only failed:', error);
  process.exit(1);
});
