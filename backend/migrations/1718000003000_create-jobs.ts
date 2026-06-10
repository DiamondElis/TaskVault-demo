import type { MigrationBuilder } from 'node-pg-migrate';

export async function up(pgm: MigrationBuilder): Promise<void> {
  pgm.createTable('jobs', {
    id: {
      type: 'uuid',
      primaryKey: true,
      default: pgm.func('gen_random_uuid()'),
    },
    file_id: {
      type: 'uuid',
      notNull: true,
      references: 'files(file_id)',
      onDelete: 'CASCADE',
    },
    type: {
      type: 'text',
      notNull: true,
    },
    status: {
      type: 'text',
      notNull: true,
      default: 'queued',
    },
    result_s3_key: {
      type: 'text',
      notNull: false,
    },
    created_at: {
      type: 'timestamptz',
      notNull: true,
      default: pgm.func('now()'),
    },
    updated_at: {
      type: 'timestamptz',
      notNull: true,
      default: pgm.func('now()'),
    },
  });

  pgm.addConstraint('jobs', 'jobs_status_check', {
    check: "status IN ('queued', 'started', 'completed', 'failed')",
  });

  pgm.createIndex('jobs', 'file_id');
  pgm.createIndex('jobs', 'status');
}

export async function down(pgm: MigrationBuilder): Promise<void> {
  pgm.dropTable('jobs');
}
