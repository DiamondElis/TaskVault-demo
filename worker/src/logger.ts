import { getConfig } from './config.js';
import * as auditRepo from './repositories/audit.repo.js';

export interface LogFields {
  event_type?: string;
  user_id?: string | null;
  s3_bucket?: string | null;
  s3_key?: string | null;
  request_id?: string;
  message?: string;
  level?: string;
  [key: string]: unknown;
}

const SERVICE_NAME = 'worker';

function shouldLog(level: string): boolean {
  const order = ['debug', 'info', 'warn', 'error'];
  const configured = getConfig().logLevel.toLowerCase();
  return order.indexOf(level) >= order.indexOf(configured);
}

export function log(level: string, fields: LogFields = {}): void {
  if (!shouldLog(level)) {
    return;
  }

  console.log(
    JSON.stringify({
      service: SERVICE_NAME,
      level,
      timestamp: new Date().toISOString(),
      ...fields,
    }),
  );
}

export async function audit(
  eventType: string,
  fields: Omit<LogFields, 'event_type' | 'service' | 'timestamp'> & { request_id: string },
): Promise<void> {
  const userId =
    typeof fields.user_id === 'string' || fields.user_id === null ? fields.user_id : null;
  const s3Bucket =
    typeof fields.s3_bucket === 'string' || fields.s3_bucket === null ? fields.s3_bucket : null;
  const s3Key = typeof fields.s3_key === 'string' || fields.s3_key === null ? fields.s3_key : null;

  const entry = {
    ...fields,
    service: SERVICE_NAME,
    event_type: eventType,
    user_id: userId,
    s3_bucket: s3Bucket,
    s3_key: s3Key,
    request_id: fields.request_id,
    timestamp: new Date().toISOString(),
  };

  console.log(JSON.stringify(entry));

  try {
    await auditRepo.insert({
      service: SERVICE_NAME,
      eventType,
      userId,
      s3Bucket,
      s3Key,
      requestId: fields.request_id,
      payload: entry as Record<string, unknown>,
    });
  } catch (error) {
    log('error', {
      event_type: 'audit_persist_failed',
      message: error instanceof Error ? error.message : 'unknown error',
      request_id: fields.request_id,
    });
  }
}
