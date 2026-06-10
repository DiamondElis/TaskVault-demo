import type { NextFunction, Request, Response } from 'express';
import client from 'prom-client';

const register = new client.Registry();
client.collectDefaultMetrics({ register });

export const httpRequestDuration = new client.Histogram({
  name: 'http_request_duration_seconds',
  help: 'HTTP request duration in seconds',
  labelNames: ['method', 'route', 'status_code'] as const,
  buckets: [0.01, 0.05, 0.1, 0.25, 0.5, 1, 2, 5],
  registers: [register],
});

export function metricsMiddleware(req: Request, res: Response, next: NextFunction): void {
  const start = process.hrtime.bigint();

  res.on('finish', () => {
    const durationNs = Number(process.hrtime.bigint() - start);
    const route = req.route?.path ? `${req.baseUrl}${req.route.path}` : req.path;
    httpRequestDuration
      .labels(req.method, route, String(res.statusCode))
      .observe(durationNs / 1_000_000_000);
  });

  next();
}

export function getMetricsRegistry(): client.Registry {
  return register;
}
