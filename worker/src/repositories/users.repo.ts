import { getPool } from '../db/pool.js';

export async function countUsers(): Promise<number> {
  const result = await getPool().query<{ count: string }>('SELECT COUNT(*)::text AS count FROM users');
  return Number(result.rows[0].count);
}
