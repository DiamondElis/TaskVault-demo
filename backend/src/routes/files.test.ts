import request from 'supertest';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { signToken } from '../auth/jwt.js';
import { createApp } from '../app.js';
import { loadConfig, setConfig } from '../config.js';
import * as s3 from '../aws/s3.js';
import * as filesRepo from '../repositories/files.repo.js';
import * as usersRepo from '../repositories/users.repo.js';

vi.mock('../aws/s3.js');
vi.mock('../repositories/files.repo.js');
vi.mock('../repositories/users.repo.js');
vi.mock('../repositories/audit.repo.js', () => ({
  insert: vi.fn().mockResolvedValue(undefined),
}));

describe('file upload', () => {
  beforeEach(() => {
    setConfig({
      ...loadConfig(),
      jwtSecret: 'test-secret',
      isTest: true,
      nodeEnv: 'test',
      s3Bucket: 'taskvault-user-files',
    });

    vi.mocked(usersRepo.findById).mockResolvedValue({
      id: 'user-1',
      email: 'demo@taskvault.test',
      password_hash: 'hash',
      role: 'user',
      created_at: new Date(),
      updated_at: new Date(),
    });

    vi.mocked(s3.buildObjectKey).mockReturnValue('uploads/sensitive/user-1/demo.csv');
    vi.mocked(s3.putObject).mockResolvedValue({
      bucket: 'taskvault-user-files',
      key: 'uploads/sensitive/user-1/demo.csv',
    });

    vi.mocked(filesRepo.createFile).mockResolvedValue({
      file_id: 'file-1',
      owner_user_id: 'user-1',
      filename: 'demo.csv',
      s3_bucket: 'taskvault-user-files',
      s3_key: 'uploads/sensitive/user-1/demo.csv',
      content_type: 'text/csv',
      size: '12',
      classification: 'sensitive',
      created_at: new Date(),
    });
  });

  it('uploads under the sensitive prefix for sensitive classification', async () => {
    const app = createApp();
    const token = signToken({ id: 'user-1', role: 'user' });

    const response = await request(app)
      .post('/api/files/upload')
      .set('Authorization', `Bearer ${token}`)
      .field('classification', 'sensitive')
      .attach('file', Buffer.from('demo,data'), 'demo.csv');

    expect(response.status).toBe(201);
    expect(s3.buildObjectKey).toHaveBeenCalledWith('sensitive', 'user-1', 'demo.csv');
    expect(s3.putObject).toHaveBeenCalled();
    expect(response.body.classification).toBe('sensitive');
  });
});
