import { getPool } from '../db/pool.js';

export interface UserRow {
  id: string;
  email: string;
  password_hash: string;
  role: string;
  created_at: Date;
  updated_at: Date;
}

export async function findByEmail(email: string): Promise<UserRow | null> {
  const result = await getPool().query<UserRow>(
    'SELECT id, email, password_hash, role, created_at, updated_at FROM users WHERE email = $1',
    [email.toLowerCase()],
  );
  return result.rows[0] ?? null;
}

export async function findById(id: string): Promise<UserRow | null> {
  const result = await getPool().query<UserRow>(
    'SELECT id, email, password_hash, role, created_at, updated_at FROM users WHERE id = $1',
    [id],
  );
  return result.rows[0] ?? null;
}

export async function createUser(
  email: string,
  passwordHash: string,
  role = 'user',
): Promise<UserRow> {
  const result = await getPool().query<UserRow>(
    `INSERT INTO users (email, password_hash, role)
     VALUES ($1, $2, $3)
     RETURNING id, email, password_hash, role, created_at, updated_at`,
    [email.toLowerCase(), passwordHash, role],
  );
  return result.rows[0];
}

export async function countUsers(): Promise<number> {
  const result = await getPool().query<{ count: string }>('SELECT COUNT(*)::text AS count FROM users');
  return Number(result.rows[0].count);
}

export async function listUsers(limit = 100, offset = 0): Promise<Omit<UserRow, 'password_hash'>[]> {
  const result = await getPool().query<Omit<UserRow, 'password_hash'>>(
    `SELECT id, email, role, created_at, updated_at
     FROM users
     ORDER BY created_at DESC
     LIMIT $1 OFFSET $2`,
    [limit, offset],
  );
  return result.rows;
}
