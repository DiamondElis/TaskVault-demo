import request from 'supertest';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { signToken } from '../auth/jwt.js';
import { createApp } from '../app.js';
import { loadConfig, setConfig } from '../config.js';
import * as tasksRepo from '../repositories/tasks.repo.js';
import * as usersRepo from '../repositories/users.repo.js';

vi.mock('../repositories/tasks.repo.js');
vi.mock('../repositories/users.repo.js');
vi.mock('../repositories/audit.repo.js', () => ({
  insert: vi.fn().mockResolvedValue(undefined),
}));

describe('tasks routes', () => {
  const token = () => signToken({ id: 'user-1', role: 'user' });

  beforeEach(() => {
    setConfig({
      ...loadConfig(),
      jwtSecret: 'test-secret',
      isTest: true,
      nodeEnv: 'test',
    });

    vi.mocked(usersRepo.findById).mockResolvedValue({
      id: 'user-1',
      email: 'demo@taskvault.test',
      password_hash: 'hash',
      role: 'user',
      created_at: new Date(),
      updated_at: new Date(),
    });
    vi.resetAllMocks();
  });

  it('creates a task for the authenticated owner', async () => {
    vi.mocked(usersRepo.findById).mockResolvedValue({
      id: 'user-1',
      email: 'demo@taskvault.test',
      password_hash: 'hash',
      role: 'user',
      created_at: new Date(),
      updated_at: new Date(),
    });

    vi.mocked(tasksRepo.createTask).mockResolvedValue({
      id: 'task-1',
      title: 'Demo',
      description: null,
      status: 'open',
      owner_user_id: 'user-1',
      created_at: new Date(),
      updated_at: new Date(),
    });

    const app = createApp();
    const response = await request(app)
      .post('/api/tasks')
      .set('Authorization', `Bearer ${token()}`)
      .send({ title: 'Demo' });

    expect(response.status).toBe(201);
    expect(response.body.title).toBe('Demo');
    expect(tasksRepo.createTask).toHaveBeenCalledWith('user-1', 'Demo', null);
  });

  it('lists tasks scoped to the owner', async () => {
    vi.mocked(usersRepo.findById).mockResolvedValue({
      id: 'user-1',
      email: 'demo@taskvault.test',
      password_hash: 'hash',
      role: 'user',
      created_at: new Date(),
      updated_at: new Date(),
    });

    vi.mocked(tasksRepo.listByOwner).mockResolvedValue([]);

    const app = createApp();
    const response = await request(app)
      .get('/api/tasks')
      .set('Authorization', `Bearer ${token()}`);

    expect(response.status).toBe(200);
    expect(tasksRepo.listByOwner).toHaveBeenCalledWith('user-1');
  });
});
