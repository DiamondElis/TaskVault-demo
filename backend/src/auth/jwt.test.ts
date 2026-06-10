import { beforeEach, describe, expect, it } from 'vitest';
import { loadConfig, setConfig } from '../config.js';
import { signToken, verifyToken } from './jwt.js';

describe('jwt', () => {
  beforeEach(() => {
    setConfig({
      ...loadConfig(),
      jwtSecret: 'test-secret',
      isTest: true,
      nodeEnv: 'test',
    });
  });

  it('signs and verifies minimal payload', () => {
    const token = signToken({ id: 'user-1', role: 'user' });
    const payload = verifyToken(token);
    expect(payload.sub).toBe('user-1');
    expect(payload.role).toBe('user');
  });
});
