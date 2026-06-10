import type { NextFunction, Request, Response } from 'express';
import { verifyToken } from '../auth/jwt.js';
import * as usersRepo from '../repositories/users.repo.js';

/**
 * Explicit unauthenticated route allowlist (vuln-1 surfaces are single, auditable entries).
 */
const PUBLIC_ROUTE_PATTERNS: Array<{ method: string; pattern: RegExp }> = [
  { method: 'GET', pattern: /^\/api\/healthz$/ },
  { method: 'GET', pattern: /^\/api\/readyz$/ },
  { method: 'GET', pattern: /^\/api\/version$/ },
  { method: 'GET', pattern: /^\/metrics$/ },
  { method: 'POST', pattern: /^\/api\/auth\/register$/ },
  { method: 'POST', pattern: /^\/api\/auth\/login$/ },
  // vuln-1: intentional unauthenticated debug surface (spec §7)
  { method: 'GET', pattern: /^\/api\/debug\/status$/ },
  // vuln-1: optional second weak surface behind feature flag (see debug routes)
  { method: 'GET', pattern: /^\/api\/admin\/reports\/preview$/ },
];

export function isPublicRoute(method: string, path: string): boolean {
  return PUBLIC_ROUTE_PATTERNS.some(
    (route) => route.method === method && route.pattern.test(path),
  );
}

export async function attachUserMiddleware(
  req: Request,
  _res: Response,
  next: NextFunction,
): Promise<void> {
  const header = req.header('authorization');
  if (!header?.startsWith('Bearer ')) {
    next();
    return;
  }

  try {
    const payload = verifyToken(header.slice(7));
    const user = await usersRepo.findById(payload.sub);
    if (user) {
      req.user = { id: user.id, email: user.email, role: user.role };
    } else {
      req.user = { id: payload.sub, email: '', role: payload.role };
    }
  } catch {
    // invalid token — leave req.user unset
  }

  next();
}

export function requireAuth(req: Request, res: Response, next: NextFunction): void {
  if (isPublicRoute(req.method, req.path)) {
    next();
    return;
  }

  if (!req.user) {
    res.status(401).json({ error: 'unauthorized' });
    return;
  }

  next();
}

export function requireAdmin(req: Request, res: Response, next: NextFunction): void {
  if (!req.user) {
    res.status(401).json({ error: 'unauthorized' });
    return;
  }

  if (req.user.role !== 'admin') {
    res.status(403).json({ error: 'forbidden' });
    return;
  }

  next();
}
