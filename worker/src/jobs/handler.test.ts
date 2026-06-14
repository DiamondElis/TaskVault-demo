import { beforeEach, describe, expect, it, vi } from 'vitest';
import { setConfig, loadConfig } from '../config.js';
import * as s3 from '../aws/s3.js';
import * as filesRepo from '../repositories/files.repo.js';
import * as jobsRepo from '../repositories/jobs.repo.js';
import * as usersRepo from '../repositories/users.repo.js';
import { processJob } from './handler.js';

vi.mock('../aws/s3.js');
vi.mock('../repositories/jobs.repo.js');
vi.mock('../repositories/files.repo.js');
vi.mock('../repositories/users.repo.js');
vi.mock('../repositories/audit.repo.js', () => ({
  insert: vi.fn().mockResolvedValue(undefined),
}));

describe('processJob', () => {
  beforeEach(() => {
    setConfig({
      ...loadConfig(),
      nodeEnv: 'test',
      isTest: true,
      s3Bucket: 'taskvault-user-files',
      reportsS3Bucket: 'taskvault-reports',
    });
    vi.resetAllMocks();
  });

  it('completes file_analysis jobs and writes a result object', async () => {
    vi.mocked(jobsRepo.findById).mockResolvedValue({
      id: 'job-1',
      file_id: 'file-1',
      type: 'file_analysis',
      status: 'queued',
      result_s3_key: null,
      created_at: new Date(),
      updated_at: new Date(),
    });

    vi.mocked(jobsRepo.updateStatus).mockImplementation(async (id, status, resultKey) => ({
      id,
      file_id: 'file-1',
      type: 'file_analysis',
      status,
      result_s3_key: resultKey ?? null,
      created_at: new Date(),
      updated_at: new Date(),
    }));

    vi.mocked(filesRepo.findById).mockResolvedValue({
      file_id: 'file-1',
      owner_user_id: 'user-1',
      filename: 'demo.csv',
      s3_bucket: 'taskvault-user-files',
      s3_key: 'uploads/private/user-1/demo.csv',
      content_type: 'text/csv',
      size: '20',
      classification: 'private',
      created_at: new Date(),
    });

    vi.mocked(s3.getObject).mockResolvedValue(Buffer.from('a,b\n1,2\n'));
    vi.mocked(s3.putObject).mockResolvedValue({
      bucket: 'taskvault-user-files',
      key: 'uploads/results/job-1.json',
    });

    const result = await processJob(
      { jobId: 'job-1', fileId: 'file-1', type: 'file_analysis' },
      'req-1',
    );

    expect(result.job.status).toBe('completed');
    expect(result.resultS3Key).toBe('uploads/results/job-1.json');
    expect(s3.getObject).toHaveBeenCalled();
    expect(s3.putObject).toHaveBeenCalled();
  });

  it('marks jobs failed when the source file is missing', async () => {
    vi.mocked(jobsRepo.findById).mockResolvedValue({
      id: 'job-2',
      file_id: 'missing-file',
      type: 'file_analysis',
      status: 'queued',
      result_s3_key: null,
      created_at: new Date(),
      updated_at: new Date(),
    });

    vi.mocked(jobsRepo.updateStatus).mockImplementation(async (id, status) => ({
      id,
      file_id: 'missing-file',
      type: 'file_analysis',
      status,
      result_s3_key: null,
      created_at: new Date(),
      updated_at: new Date(),
    }));

    vi.mocked(filesRepo.findById).mockResolvedValue(null);

    await expect(
      processJob(
        { jobId: 'job-2', fileId: 'missing-file', type: 'file_analysis' },
        'req-2',
      ),
    ).rejects.toThrow('File not found');

    expect(jobsRepo.updateStatus).toHaveBeenCalledWith('job-2', 'failed');
  });

  it('writes admin report objects for admin_report jobs', async () => {
    vi.mocked(jobsRepo.findById).mockResolvedValue({
      id: 'job-3',
      file_id: 'file-1',
      type: 'admin_report',
      status: 'queued',
      result_s3_key: null,
      created_at: new Date(),
      updated_at: new Date(),
    });

    vi.mocked(jobsRepo.updateStatus).mockImplementation(async (id, status, resultKey) => ({
      id,
      file_id: 'file-1',
      type: 'admin_report',
      status,
      result_s3_key: resultKey ?? null,
      created_at: new Date(),
      updated_at: new Date(),
    }));

    vi.mocked(usersRepo.countUsers).mockResolvedValue(2);
    vi.mocked(filesRepo.countFiles).mockResolvedValue(5);
    vi.mocked(filesRepo.countSensitiveFiles).mockResolvedValue(1);
    vi.mocked(s3.putObject).mockResolvedValue({
      bucket: 'taskvault-reports',
      key: 'reports/admin/report-job-3.json',
    });

    const result = await processJob(
      { jobId: 'job-3', fileId: 'file-1', type: 'admin_report' },
      'req-3',
    );

    expect(result.job.status).toBe('completed');
    expect(s3.putObject).toHaveBeenCalledWith(
      expect.objectContaining({ bucket: 'taskvault-reports' }),
    );
  });
});
