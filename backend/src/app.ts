import express from 'express';
import { attachUserMiddleware, requireAuth } from './middleware/auth.js';
import { metricsMiddleware } from './middleware/metrics.js';
import { requestIdMiddleware } from './middleware/request-id.js';
import adminRouter from './routes/admin.js';
import authRouter from './routes/auth.js';
import debugRouter from './routes/debug.js';
import filesRouter from './routes/files.js';
import healthRouter from './routes/health.js';
import metricsRouter from './routes/metrics.js';
import tasksRouter from './routes/tasks.js';

export function createApp(): express.Application {
  const app = express();

  app.use(requestIdMiddleware);
  app.use(metricsMiddleware);
  app.use(express.json());
  app.use(express.urlencoded({ extended: true }));
  app.use(attachUserMiddleware);

  app.use(healthRouter);
  app.use(metricsRouter);
  app.use(debugRouter);
  app.use(authRouter);
  app.use('/api/tasks', tasksRouter);
  app.use('/api/files', filesRouter);
  app.use('/api/admin', adminRouter);

  app.get('/api', requireAuth, (_req, res) => {
    res.status(200).json({ service: 'backend-api', status: 'placeholder' });
  });

  return app;
}
