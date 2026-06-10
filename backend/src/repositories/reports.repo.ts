import { getPool } from '../db/pool.js';

export interface ReportRow {
  id: string;
  requested_by: string;
  user_count: number;
  file_count: number;
  sensitive_file_count: number;
  report_s3_key: string;
  created_at: Date;
}

export async function createReport(input: {
  requestedBy: string;
  userCount: number;
  fileCount: number;
  sensitiveFileCount: number;
  reportS3Key: string;
}): Promise<ReportRow> {
  const result = await getPool().query<ReportRow>(
    `INSERT INTO reports (requested_by, user_count, file_count, sensitive_file_count, report_s3_key)
     VALUES ($1, $2, $3, $4, $5)
     RETURNING id, requested_by, user_count, file_count, sensitive_file_count, report_s3_key, created_at`,
    [
      input.requestedBy,
      input.userCount,
      input.fileCount,
      input.sensitiveFileCount,
      input.reportS3Key,
    ],
  );
  return result.rows[0];
}

export async function listReports(limit = 50, offset = 0): Promise<ReportRow[]> {
  const result = await getPool().query<ReportRow>(
    `SELECT id, requested_by, user_count, file_count, sensitive_file_count, report_s3_key, created_at
     FROM reports
     ORDER BY created_at DESC
     LIMIT $1 OFFSET $2`,
    [limit, offset],
  );
  return result.rows;
}
