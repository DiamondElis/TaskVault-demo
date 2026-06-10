import jwt from 'jsonwebtoken';
import { getConfig } from '../config.js';
import type { AuthUser, JwtPayload } from './types.js';

export function signToken(user: Pick<AuthUser, 'id' | 'role'>): string {
  const payload: JwtPayload = { sub: user.id, role: user.role };
  return jwt.sign(payload, getConfig().jwtSecret, { expiresIn: '24h' });
}

export function verifyToken(token: string): JwtPayload {
  return jwt.verify(token, getConfig().jwtSecret) as JwtPayload;
}
