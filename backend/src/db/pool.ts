import pg from 'pg';
import { getConfig } from '../config.js';

let pool: pg.Pool | undefined;

export function initPool(databaseUrl?: string): pg.Pool {
  if (pool) {
    return pool;
  }

  const url = databaseUrl ?? getConfig().databaseUrl;
  pool = new pg.Pool({ connectionString: url });
  return pool;
}

export function getPool(): pg.Pool {
  if (!pool) {
    return initPool();
  }
  return pool;
}

export async function checkDatabaseConnectivity(): Promise<boolean> {
  try {
    await getPool().query('SELECT 1');
    return true;
  } catch {
    return false;
  }
}

export async function closePool(): Promise<void> {
  if (pool) {
    await pool.end();
    pool = undefined;
  }
}
