import client from 'prom-client';

const register = new client.Registry();
client.collectDefaultMetrics({ register });

export const jobsProcessedTotal = new client.Counter({
  name: 'worker_jobs_processed_total',
  help: 'Total jobs processed by the worker',
  labelNames: ['status', 'job_type'] as const,
  registers: [register],
});

export const jobProcessingDuration = new client.Histogram({
  name: 'worker_job_processing_duration_seconds',
  help: 'Job processing duration in seconds',
  labelNames: ['job_type'] as const,
  buckets: [0.05, 0.1, 0.25, 0.5, 1, 2, 5, 10],
  registers: [register],
});

export function getMetricsRegistry(): client.Registry {
  return register;
}
