import { getPool } from '../db/pool.js';

export type FileClassification = 'public' | 'private' | 'sensitive';

export interface FileRow {
  file_id: string;
  owner_user_id: string;
  filename: string;
  s3_bucket: string;
  s3_key: string;
  content_type: string;
  size: string;
  classification: FileClassification;
  created_at: Date;
}

export async function createFile(input: {
  ownerUserId: string;
  filename: string;
  s3Bucket: string;
  s3Key: string;
  contentType: string;
  size: number;
  classification: FileClassification;
}): Promise<FileRow> {
  const result = await getPool().query<FileRow>(
    `INSERT INTO files (owner_user_id, filename, s3_bucket, s3_key, content_type, size, classification)
     VALUES ($1, $2, $3, $4, $5, $6, $7)
     RETURNING file_id, owner_user_id, filename, s3_bucket, s3_key, content_type, size::text, classification, created_at`,
    [
      input.ownerUserId,
      input.filename,
      input.s3Bucket,
      input.s3Key,
      input.contentType,
      input.size,
      input.classification,
    ],
  );
  return result.rows[0];
}

export async function findById(fileId: string): Promise<FileRow | null> {
  const result = await getPool().query<FileRow>(
    `SELECT file_id, owner_user_id, filename, s3_bucket, s3_key, content_type, size::text, classification, created_at
     FROM files WHERE file_id = $1`,
    [fileId],
  );
  return result.rows[0] ?? null;
}

export async function listByOwner(ownerUserId: string): Promise<FileRow[]> {
  const result = await getPool().query<FileRow>(
    `SELECT file_id, owner_user_id, filename, s3_bucket, s3_key, content_type, size::text, classification, created_at
     FROM files WHERE owner_user_id = $1
     ORDER BY created_at DESC`,
    [ownerUserId],
  );
  return result.rows;
}

export async function listAll(limit = 100, offset = 0): Promise<FileRow[]> {
  const result = await getPool().query<FileRow>(
    `SELECT file_id, owner_user_id, filename, s3_bucket, s3_key, content_type, size::text, classification, created_at
     FROM files
     ORDER BY created_at DESC
     LIMIT $1 OFFSET $2`,
    [limit, offset],
  );
  return result.rows;
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
