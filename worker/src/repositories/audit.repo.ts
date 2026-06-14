import { getPool } from '../db/pool.js';

export async function insert(input: {
  service: string;
  eventType: string;
  userId?: string | null;
  s3Bucket?: string | null;
  s3Key?: string | null;
  requestId: string;
  payload: Record<string, unknown>;
}): Promise<void> {
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
