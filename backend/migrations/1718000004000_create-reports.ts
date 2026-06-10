import type { MigrationBuilder } from 'node-pg-migrate';

export async function up(pgm: MigrationBuilder): Promise<void> {
  pgm.createTable('reports', {
    id: {
      type: 'uuid',
      primaryKey: true,
      default: pgm.func('gen_random_uuid()'),
    },
    requested_by: {
      type: 'uuid',
      notNull: true,
      references: 'users(id)',
      onDelete: 'CASCADE',
    },
    user_count: {
      type: 'integer',
      notNull: true,
    },
    file_count: {
      type: 'integer',
      notNull: true,
    },
    sensitive_file_count: {
      type: 'integer',
      notNull: true,
    },
    report_s3_key: {
      type: 'text',
      notNull: true,
    },
    created_at: {
      type: 'timestamptz',
      notNull: true,
      default: pgm.func('now()'),
    },
  });

  pgm.createIndex('reports', 'requested_by');
}

export async function down(pgm: MigrationBuilder): Promise<void> {
  pgm.dropTable('reports');
}
