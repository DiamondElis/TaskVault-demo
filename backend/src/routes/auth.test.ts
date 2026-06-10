import bcrypt from 'bcryptjs';
import request from 'supertest';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { createApp } from '../app.js';
import { loadConfig, setConfig } from '../config.js';
import * as usersRepo from '../repositories/users.repo.js';

vi.mock('../repositories/users.repo.js');
vi.mock('../repositories/audit.repo.js', () => ({
  insert: vi.fn().mockResolvedValue(undefined),
}));

describe('auth routes', () => {
  beforeEach(() => {
    setConfig({
      ...loadConfig(),
      jwtSecret: 'test-secret',
      isTest: true,
      nodeEnv: 'test',
    });
    vi.resetAllMocks();
  });

  it('registers a user and returns a JWT', async () => {
    vi.mocked(usersRepo.findByEmail).mockResolvedValue(null);
    vi.mocked(usersRepo.createUser).mockResolvedValue({
      id: 'user-1',
      email: 'demo@taskvault.test',
      password_hash: 'hash',
      role: 'user',
      created_at: new Date(),
      updated_at: new Date(),
    });

    const app = createApp();
    const response = await request(app)
      .post('/api/auth/register')
      .send({ email: 'demo@taskvault.test', password: 'password123' });

    expect(response.status).toBe(201);
    expect(response.body.token).toBeTypeOf('string');
    expect(response.body.user.email).toBe('demo@taskvault.test');
  });

  it('logs in with valid credentials', async () => {
    const hash = await bcrypt.hash('password123', 10);
    vi.mocked(usersRepo.findByEmail).mockResolvedValue({
      id: 'user-1',
      email: 'demo@taskvault.test',
      password_hash: hash,
      role: 'user',
      created_at: new Date(),
      updated_at: new Date(),
    });

    const app = createApp();
    const response = await request(app)
      .post('/api/auth/login')
      .send({ email: 'demo@taskvault.test', password: 'password123' });

    expect(response.status).toBe(200);
    expect(response.body.token).toBeTypeOf('string');
  });
});
