#!/usr/bin/env tsx
import './load-env.js';
import { runMigrations } from './migrate.js';

const direction = process.argv[2] === 'down' ? 'down' : 'up';

runMigrations(direction).catch((error: unknown) => {
  console.error(`migrate:${direction} failed:`, error);
  process.exit(1);
});
