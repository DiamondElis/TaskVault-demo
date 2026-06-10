import type { MigrationBuilder } from 'node-pg-migrate';

export async function up(pgm: MigrationBuilder): Promise<void> {
  pgm.createTable('audit_events', {
    id: {
      type: 'uuid',
      primaryKey: true,
      default: pgm.func('gen_random_uuid()'),
    },
    service: {
      type: 'text',
      notNull: true,
    },
    event_type: {
      type: 'text',
      notNull: true,
    },
    user_id: {
      type: 'text',
      notNull: false,
    },
    s3_bucket: {
      type: 'text',
      notNull: false,
    },
    s3_key: {
      type: 'text',
      notNull: false,
    },
    request_id: {
      type: 'text',
      notNull: true,
    },
    payload: {
      type: 'jsonb',
      notNull: true,
      default: pgm.func("'{}'::jsonb"),
    },
    timestamp: {
      type: 'timestamptz',
      notNull: true,
      default: pgm.func('now()'),
    },
  });

  pgm.createIndex('audit_events', 'event_type');
  pgm.createIndex('audit_events', 'timestamp');
  pgm.createIndex('audit_events', 'user_id');
}

export async function down(pgm: MigrationBuilder): Promise<void> {
  pgm.dropTable('audit_events');
}
