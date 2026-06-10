import { Router } from 'express';
import { getConfig } from '../config.js';
import { checkDatabaseConnectivity } from '../db/pool.js';

const router = Router();

router.get('/api/healthz', (_req, res) => {
  res.status(200).json({ status: 'ok' });
});

router.get('/api/readyz', async (_req, res) => {
  const dbReady = await checkDatabaseConnectivity();
  if (!dbReady) {
    res.status(503).json({ status: 'not_ready', database: false });
    return;
  }

  res.status(200).json({ status: 'ready', database: true });
});

router.get('/api/version', (_req, res) => {
  const config = getConfig();
  res.status(200).json({
    service: 'backend-api',
    buildSha: config.buildSha,
    region: config.awsRegion,
  });
});

export default router;
