import { PutObjectCommand } from '@aws-sdk/client-s3';
import bcrypt from 'bcryptjs';
import { getConfig } from '../config.js';
import { getS3Client } from '../aws/clients.js';
import { getPool } from './pool.js';

export const SENSITIVE_FIXTURES = [
  {
    key: 'uploads/sensitive/payroll-export-demo.csv',
    filename: 'payroll-export-demo.csv',
    body: 'employee_id,name,amount\n1,Demo User,1000\n2,Demo User,1200\n',
  },
  {
    key: 'uploads/sensitive/customer-records-demo.csv',
    filename: 'customer-records-demo.csv',
    body: 'customer_id,segment,status\nC-001,demo,active\nC-002,demo,active\n',
  },
  {
    key: 'uploads/sensitive/internal-access-review-demo.csv',
    filename: 'internal-access-review-demo.csv',
    body: 'system,access_level,reviewer\nvault,read,demo-admin\n',
  },
] as const;

const DEMO_TASKS = [
  { title: 'Review quarterly access logs', description: 'Demo backlog item', status: 'open' },
  { title: 'Onboard contractor accounts', description: 'Demo backlog item', status: 'in_progress' },
  { title: 'Archive stale payroll exports', description: 'Demo backlog item', status: 'done' },
] as const;

export async function seedDemoData(): Promise<void> {
  const adminUserId = await seedUsers();
  await seedTasks(adminUserId);
  const fileIds = await seedFileMetadata(adminUserId);
  await seedDemoJobs(fileIds);
  await seedS3Fixtures();
}

async function seedUsers(): Promise<string> {
  const adminEmail = process.env.DEMO_ADMIN_EMAIL ?? 'admin@taskvault.demo';
  const adminPassword = process.env.DEMO_ADMIN_PASSWORD ?? 'password123';
  const demoUserEmail = process.env.DEMO_USER_EMAIL ?? 'user@taskvault.demo';
  const demoUserPassword = process.env.DEMO_USER_PASSWORD ?? 'password123';

  const adminHash = await bcrypt.hash(adminPassword, 10);
  const userHash = await bcrypt.hash(demoUserPassword, 10);

  const adminResult = await getPool().query<{ id: string }>(
    `INSERT INTO users (email, password_hash, role)
     VALUES ($1, $2, 'admin')
     ON CONFLICT (email) DO UPDATE SET role = 'admin', password_hash = EXCLUDED.password_hash
     RETURNING id`,
    [adminEmail.toLowerCase(), adminHash],
  );

  await getPool().query(
    `INSERT INTO users (email, password_hash, role)
     VALUES ($1, $2, 'user')
     ON CONFLICT (email) DO UPDATE SET password_hash = EXCLUDED.password_hash`,
    [demoUserEmail.toLowerCase(), userHash],
  );

  console.log(`Demo admin ready: ${adminEmail}`);
  console.log(`Demo user ready: ${demoUserEmail}`);
  return adminResult.rows[0].id;
}

async function seedTasks(ownerUserId: string): Promise<void> {
  for (const task of DEMO_TASKS) {
    await getPool().query(
      `INSERT INTO tasks (title, description, status, owner_user_id)
       SELECT $1, $2, $3, $4
       WHERE NOT EXISTS (
         SELECT 1 FROM tasks WHERE title = $1 AND owner_user_id = $4
       )`,
      [task.title, task.description, task.status, ownerUserId],
    );
  }

  console.log(`Demo tasks ready (${DEMO_TASKS.length} rows).`);
}

async function seedFileMetadata(ownerUserId: string): Promise<string[]> {
  const config = getConfig();
  const fileIds: string[] = [];

  for (const fixture of SENSITIVE_FIXTURES) {
    const size = Buffer.byteLength(fixture.body, 'utf8');
    const result = await getPool().query<{ file_id: string }>(
      `INSERT INTO files (
         owner_user_id, filename, s3_bucket, s3_key, content_type, size, classification
       )
       SELECT $1, $2, $3, $4, 'text/csv', $5, 'sensitive'
       WHERE NOT EXISTS (SELECT 1 FROM files WHERE s3_key = $4)
       RETURNING file_id`,
      [ownerUserId, fixture.filename, config.s3Bucket, fixture.key, size],
    );

    if (result.rows[0]) {
      fileIds.push(result.rows[0].file_id);
    } else {
      const existing = await getPool().query<{ file_id: string }>(
        `SELECT file_id FROM files WHERE s3_key = $1 LIMIT 1`,
        [fixture.key],
      );
      if (existing.rows[0]) {
        fileIds.push(existing.rows[0].file_id);
      }
    }
  }

  console.log(`Demo file metadata ready (${fileIds.length} sensitive rows).`);
  return fileIds;
}

async function seedDemoJobs(fileIds: string[]): Promise<void> {
  if (fileIds.length === 0) {
    return;
  }

  const primaryFileId = fileIds[0];
  await getPool().query(
    `INSERT INTO jobs (file_id, type, status, result_s3_key)
     SELECT $1, 'file_analysis', 'completed', $2
     WHERE NOT EXISTS (
       SELECT 1 FROM jobs WHERE file_id = $1 AND type = 'file_analysis' AND status = 'completed'
     )`,
    [primaryFileId, `results/analysis/${primaryFileId}.json`],
  );

  await getPool().query(
    `INSERT INTO jobs (file_id, type, status, result_s3_key)
     SELECT $1, 'admin_report', 'completed', $2
     WHERE NOT EXISTS (
       SELECT 1 FROM jobs WHERE type = 'admin_report' AND status = 'completed'
     )`,
    [primaryFileId, `reports/admin/report-seed-demo.json`],
  );

  console.log('Demo job rows ready.');
}

async function seedS3Fixtures(): Promise<void> {
  if (process.env.SEED_SKIP_S3_FIXTURES === 'true') {
    console.log('Skipping S3 fixture upload (SEED_SKIP_S3_FIXTURES=true).');
    return;
  }

  const config = getConfig();
  const client = getS3Client();

  for (const fixture of SENSITIVE_FIXTURES) {
    await client.send(
      new PutObjectCommand({
        Bucket: config.s3Bucket,
        Key: fixture.key,
        Body: fixture.body,
        ContentType: 'text/csv',
      }),
    );
    console.log(`Uploaded fixture s3://${config.s3Bucket}/${fixture.key}`);
  }
}
