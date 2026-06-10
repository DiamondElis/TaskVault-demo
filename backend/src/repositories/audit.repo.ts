import { getPool } from '../db/pool.js';

export interface AuditInsert {
  service: string;
  eventType: string;
  userId?: string | null;
  s3Bucket?: string | null;
  s3Key?: string | null;
  requestId: string;
  payload: Record<string, unknown>;
}

export interface AuditRow {
  id: string;
  service: string;
  event_type: string;
  user_id: string | null;
  s3_bucket: string | null;
  s3_key: string | null;
  request_id: string;
  payload: Record<string, unknown>;
  timestamp: Date;
}

export async function insert(input: AuditInsert): Promise<void> {
  await getPool().query(
    `INSERT INTO audit_events (service, event_type, user_id, s3_bucket, s3_key, request_id, payload)
     VALUES ($1, $2, $3, $4, $5, $6, $7::jsonb)`,
    [
      input.service,
      input.eventType,
      input.userId ?? null,
      input.s3Bucket ?? null,
      input.s3Key ?? null,
      input.requestId,
      JSON.stringify(input.payload),
    ],
  );
}

export async function list(limit = 50, offset = 0): Promise<AuditRow[]> {
  const result = await getPool().query<AuditRow>(
    `SELECT id, service, event_type, user_id, s3_bucket, s3_key, request_id, payload, timestamp
     FROM audit_events
     ORDER BY timestamp DESC
     LIMIT $1 OFFSET $2`,
    [limit, offset],
  );
  return result.rows;
}
