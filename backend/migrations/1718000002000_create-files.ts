import type { MigrationBuilder } from 'node-pg-migrate';

export async function up(pgm: MigrationBuilder): Promise<void> {
  pgm.createTable('files', {
    file_id: {
      type: 'uuid',
      primaryKey: true,
      default: pgm.func('gen_random_uuid()'),
    },
    owner_user_id: {
      type: 'uuid',
      notNull: true,
      references: 'users(id)',
      onDelete: 'CASCADE',
    },
    filename: {
      type: 'text',
      notNull: true,
    },
    s3_bucket: {
      type: 'text',
      notNull: true,
    },
    s3_key: {
      type: 'text',
      notNull: true,
    },
    content_type: {
      type: 'text',
      notNull: true,
    },
    size: {
      type: 'bigint',
      notNull: true,
    },
    classification: {
      type: 'text',
      notNull: true,
    },
    created_at: {
      type: 'timestamptz',
      notNull: true,
      default: pgm.func('now()'),
    },
  });

  pgm.addConstraint('files', 'files_classification_check', {
    check: "classification IN ('public', 'private', 'sensitive')",
  });

  pgm.createIndex('files', 'owner_user_id');
  pgm.createIndex('files', 'classification');
}

export async function down(pgm: MigrationBuilder): Promise<void> {
  pgm.dropTable('files');
}
