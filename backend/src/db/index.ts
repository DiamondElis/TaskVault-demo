import pg from 'pg';

/**
 * Migration tooling: node-pg-migrate (not Knex).
 *
 * Chosen for explicit SQL-oriented migrations with a small API, built-in
 * `pgmigrations` tracking (idempotent `up`), and no query-builder layer we
 * do not need yet. Knex would add ORM-style builders; node-pg-migrate keeps
 * schema changes visible as plain migration files under backend/migrations/.
 */
export function getDatabaseUrl(): string {
  const url = process.env.DATABASE_URL;
  if (!url) {
    throw new Error('DATABASE_URL is required');
  }
  return url;
}

export function createPool(): pg.Pool {
  return new pg.Pool({ connectionString: getDatabaseUrl() });
}

export { pg };
