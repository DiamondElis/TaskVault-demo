import express from 'express';
import { randomUUID } from 'node:crypto';
import { checkSqsReachability } from './aws/sqs.js';
import { checkDatabaseConnectivity } from './db/pool.js';
import { processJob } from './jobs/handler.js';
import { getMetricsRegistry } from './metrics.js';
import * as jobsRepo from './repositories/jobs.repo.js';
import type { JobMessage } from './aws/sqs.js';

export function createApp(): express.Application {
  const app = express();

  app.use((_req, res, next) => {
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
    next();
  });

  app.options('*', (_req, res) => {
    res.sendStatus(204);
  });

  app.use(express.json());

  app.get('/worker/healthz', (_req, res) => {
    res.status(200).json({ status: 'ok' });
  });

  app.get('/worker/readyz', async (_req, res) => {
    const [database, sqs] = await Promise.all([
      checkDatabaseConnectivity(),
      checkSqsReachability(),
    ]);

    if (!database || !sqs) {
      res.status(503).json({ status: 'not_ready', database, sqs });
      return;
    }

    res.status(200).json({ status: 'ready', database, sqs });
  });

  app.get('/metrics', async (_req, res) => {
    res.setHeader('Content-Type', getMetricsRegistry().contentType);
    res.end(await getMetricsRegistry().metrics());
  });

  app.post('/internal/jobs/process', async (req, res) => {
    const body = req.body as JobMessage;
    if (!body?.jobId || !body?.type) {
      res.status(400).json({ error: 'invalid_job_message' });
      return;
    }

    try {
      const result = await processJob(body, randomUUID());
      res.status(200).json(result);
    } catch (error) {
      res.status(500).json({
        error: error instanceof Error ? error.message : 'job_processing_failed',
      });
    }
  });

  app.get('/internal/jobs/:id', async (req, res) => {
    const job = await jobsRepo.findById(req.params.id);
    if (!job) {
      res.status(404).json({ error: 'not_found' });
      return;
    }

    res.status(200).json(job);
  });

  return app;
}
