import { getPool } from '../db/pool.js';

export interface FileRow {
  file_id: string;
  owner_user_id: string;
  filename: string;
  s3_bucket: string;
  s3_key: string;
  content_type: string;
  size: string;
  classification: string;
  created_at: Date;
}

export async function findById(fileId: string): Promise<FileRow | null> {
  const result = await getPool().query<FileRow>(
    `SELECT file_id, owner_user_id, filename, s3_bucket, s3_key, content_type, size::text, classification, created_at
     FROM files WHERE file_id = $1`,
    [fileId],
  );
  return result.rows[0] ?? null;
}

export async function countFiles(): Promise<number> {
  const result = await getPool().query<{ count: string }>('SELECT COUNT(*)::text AS count FROM files');
  return Number(result.rows[0].count);
}

export async function countSensitiveFiles(): Promise<number> {
  const result = await getPool().query<{ count: string }>(
    `SELECT COUNT(*)::text AS count FROM files WHERE classification = 'sensitive'`,
  );
  return Number(result.rows[0].count);
}
