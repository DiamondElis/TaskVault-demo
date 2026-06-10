import bcrypt from 'bcryptjs';
import { Router } from 'express';
import { signToken } from '../auth/jwt.js';
import { audit, log } from '../logger.js';
import { requireAuth } from '../middleware/auth.js';
import * as usersRepo from '../repositories/users.repo.js';

const router = Router();

function isValidEmail(email: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
}

router.post('/api/auth/register', async (req, res) => {
  const email = String(req.body?.email ?? '').trim();
  const password = String(req.body?.password ?? '');

  if (!isValidEmail(email) || password.length < 8) {
    res.status(400).json({ error: 'invalid_email_or_password' });
    return;
  }

  const existing = await usersRepo.findByEmail(email);
  if (existing) {
    res.status(409).json({ error: 'email_already_registered' });
    return;
  }

  const passwordHash = await bcrypt.hash(password, 10);
  const user = await usersRepo.createUser(email, passwordHash);
  const token = signToken(user);

  log('info', {
    event_type: 'user_registered',
    user_id: user.id,
    request_id: req.requestId,
  });

  res.status(201).json({
    token,
    user: { id: user.id, email: user.email, role: user.role },
  });
});

router.post('/api/auth/login', async (req, res) => {
  const email = String(req.body?.email ?? '').trim();
  const password = String(req.body?.password ?? '');

  const user = await usersRepo.findByEmail(email);
  if (!user || !(await bcrypt.compare(password, user.password_hash))) {
    await audit('login_failure', {
      user_id: null,
      request_id: req.requestId,
      email,
    });
    res.status(401).json({ error: 'invalid_credentials' });
    return;
  }

  const token = signToken(user);

  await audit('login_success', {
    user_id: user.id,
    request_id: req.requestId,
  });

  res.status(200).json({
    token,
    user: { id: user.id, email: user.email, role: user.role },
  });
});

router.post('/api/auth/logout', requireAuth, async (req, res) => {
  await audit('logout', {
    user_id: req.user?.id ?? null,
    request_id: req.requestId,
  });

  res.status(200).json({ ok: true });
});

router.get('/api/me', requireAuth, async (req, res) => {
  const user = await usersRepo.findById(req.user!.id);
  if (!user) {
    res.status(404).json({ error: 'not_found' });
    return;
  }

  res.status(200).json({
    id: user.id,
    email: user.email,
    role: user.role,
  });
});

export default router;
