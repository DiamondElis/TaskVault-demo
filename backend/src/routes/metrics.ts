import { Router } from 'express';
import { getMetricsRegistry } from '../middleware/metrics.js';

const router = Router();

router.get('/metrics', async (_req, res) => {
  res.setHeader('Content-Type', getMetricsRegistry().contentType);
  res.end(await getMetricsRegistry().metrics());
});

export default router;
