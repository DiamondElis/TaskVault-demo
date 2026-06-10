import { getPool } from '../db/pool.js';

export interface TaskRow {
  id: string;
  title: string;
  description: string | null;
  status: string;
  owner_user_id: string;
  created_at: Date;
  updated_at: Date;
}

export async function createTask(
  ownerUserId: string,
  title: string,
  description: string | null,
): Promise<TaskRow> {
  const result = await getPool().query<TaskRow>(
    `INSERT INTO tasks (title, description, owner_user_id)
     VALUES ($1, $2, $3)
     RETURNING id, title, description, status, owner_user_id, created_at, updated_at`,
    [title, description, ownerUserId],
  );
  return result.rows[0];
}

export async function findById(id: string): Promise<TaskRow | null> {
  const result = await getPool().query<TaskRow>(
    `SELECT id, title, description, status, owner_user_id, created_at, updated_at
     FROM tasks WHERE id = $1`,
    [id],
  );
  return result.rows[0] ?? null;
}

export async function listByOwner(ownerUserId: string): Promise<TaskRow[]> {
  const result = await getPool().query<TaskRow>(
    `SELECT id, title, description, status, owner_user_id, created_at, updated_at
     FROM tasks WHERE owner_user_id = $1
     ORDER BY created_at DESC`,
    [ownerUserId],
  );
  return result.rows;
}

export async function updateTask(
  id: string,
  ownerUserId: string,
  updates: { title?: string; description?: string | null; status?: string },
): Promise<TaskRow | null> {
  const result = await getPool().query<TaskRow>(
    `UPDATE tasks
     SET title = COALESCE($3, title),
         description = COALESCE($4, description),
         status = COALESCE($5, status),
         updated_at = now()
     WHERE id = $1 AND owner_user_id = $2
     RETURNING id, title, description, status, owner_user_id, created_at, updated_at`,
    [id, ownerUserId, updates.title ?? null, updates.description ?? null, updates.status ?? null],
  );
  return result.rows[0] ?? null;
}

export async function deleteTask(id: string, ownerUserId: string): Promise<boolean> {
  const result = await getPool().query(
    'DELETE FROM tasks WHERE id = $1 AND owner_user_id = $2',
    [id, ownerUserId],
  );
  return (result.rowCount ?? 0) > 0;
}
