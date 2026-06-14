import { getPool } from '../db/pool.js';

export interface JobRow {
  id: string;
  file_id: string;
  type: string;
  status: string;
  result_s3_key: string | null;
  created_at: Date;
  updated_at: Date;
}

export async function findById(id: string): Promise<JobRow | null> {
  const result = await getPool().query<JobRow>(
    `SELECT id, file_id, type, status, result_s3_key, created_at, updated_at
     FROM jobs WHERE id = $1`,
    [id],
  );
  return result.rows[0] ?? null;
}

export async function updateStatus(
  id: string,
  status: string,
  resultS3Key?: string | null,
): Promise<JobRow | null> {
  const result = await getPool().query<JobRow>(
    `UPDATE jobs
     SET status = $2,
         result_s3_key = COALESCE($3, result_s3_key),
         updated_at = now()
     WHERE id = $1
     RETURNING id, file_id, type, status, result_s3_key, created_at, updated_at`,
    [id, status, resultS3Key ?? null],
  );
  return result.rows[0] ?? null;
}
