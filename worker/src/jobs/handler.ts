import { randomUUID } from 'node:crypto';
import * as s3 from '../aws/s3.js';
import type { JobMessage } from '../aws/sqs.js';
import { getConfig } from '../config.js';
import { audit, log } from '../logger.js';
import * as filesRepo from '../repositories/files.repo.js';
import * as jobsRepo from '../repositories/jobs.repo.js';
import * as usersRepo from '../repositories/users.repo.js';
import { buildFakeAnalysis } from './analysis.js';

export interface ProcessJobResult {
  job: jobsRepo.JobRow;
  resultS3Key: string;
}

export async function processJob(
  message: JobMessage,
  requestId: string = randomUUID(),
): Promise<ProcessJobResult> {
  const job = await jobsRepo.findById(message.jobId);
  if (!job) {
    throw new Error(`Job not found: ${message.jobId}`);
  }

  await jobsRepo.updateStatus(job.id, 'started');

  try {
    if (job.type === 'admin_report') {
      return await processAdminReport(job.id, requestId);
    }

    return await processFileAnalysis(job, message.fileId, requestId);
  } catch (error) {
    await jobsRepo.updateStatus(job.id, 'failed');
    log('error', {
      event_type: 'worker_job_failed',
      request_id: requestId,
      job_id: job.id,
      message: error instanceof Error ? error.message : 'unknown error',
    });
    throw error;
  }
}

async function processFileAnalysis(
  job: jobsRepo.JobRow,
  fileId: string,
  requestId: string,
): Promise<ProcessJobResult> {
  const file = await filesRepo.findById(fileId);
  if (!file) {
    throw new Error(`File not found: ${fileId}`);
  }

  const objectBytes = await s3.getObject(file.s3_bucket, file.s3_key);
  const analysis = buildFakeAnalysis(objectBytes, file.filename);
  const resultKey = `uploads/results/${job.id}.json`;
  const resultBody = Buffer.from(
    JSON.stringify(
      {
        jobId: job.id,
        fileId: file.file_id,
        source: { bucket: file.s3_bucket, key: file.s3_key },
        analysis,
      },
      null,
      2,
    ),
  );

  const { bucket, key } = await s3.putObject({
    bucket: getConfig().s3Bucket,
    key: resultKey,
    body: resultBody,
    contentType: 'application/json',
  });

  const updated = await jobsRepo.updateStatus(job.id, 'completed', key);
  if (!updated) {
    throw new Error(`Failed to update job ${job.id}`);
  }

  await audit('worker_job_completed', {
    request_id: requestId,
    job_id: job.id,
    file_id: file.file_id,
    s3_bucket: bucket,
    s3_key: key,
  });

  return { job: updated, resultS3Key: key };
}

async function processAdminReport(jobId: string, requestId: string): Promise<ProcessJobResult> {
  const [userCount, fileCount, sensitiveFileCount] = await Promise.all([
    usersRepo.countUsers(),
    filesRepo.countFiles(),
    filesRepo.countSensitiveFiles(),
  ]);

  const reportKey = `reports/admin/report-${jobId}.json`;
  const reportBody = Buffer.from(
    JSON.stringify(
      {
        jobId,
        userCount,
        fileCount,
        sensitiveFileCount,
        generatedAt: new Date().toISOString(),
      },
      null,
      2,
    ),
  );

  const { bucket, key } = await s3.putObject({
    bucket: getConfig().reportsS3Bucket,
    key: reportKey,
    body: reportBody,
    contentType: 'application/json',
  });

  const updated = await jobsRepo.updateStatus(jobId, 'completed', key);
  if (!updated) {
    throw new Error(`Failed to update job ${jobId}`);
  }

  await audit('admin_report_written', {
    request_id: requestId,
    job_id: jobId,
    s3_bucket: bucket,
    s3_key: key,
    user_count: userCount,
    file_count: fileCount,
    sensitive_file_count: sensitiveFileCount,
  });

  await audit('worker_job_completed', {
    request_id: requestId,
    job_id: jobId,
    s3_bucket: bucket,
    s3_key: key,
  });

  return { job: updated, resultS3Key: key };
}
