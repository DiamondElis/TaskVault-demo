import { createApp } from './app.js';
import { resolveRuntimeSecrets } from './aws/secrets.js';
import { runConsumerLoop, waitForInFlightDrain } from './consumer.js';
import { getConfig, loadConfig } from './config.js';
import { initPool, closePool } from './db/pool.js';
import { log } from './logger.js';

async function bootstrap(): Promise<void> {
  loadConfig();
  await resolveRuntimeSecrets();
  initPool(getConfig().databaseUrl);

  const abortController = new AbortController();
  const app = createApp();
  const config = getConfig();

  const server = app.listen(config.port, () => {
    log('info', {
      event_type: 'worker_http_started',
      message: `worker listening on :${config.port}`,
      request_id: 'worker-boot',
    });
  });

  void runConsumerLoop({ abortSignal: abortController.signal });

  const shutdown = async (signal: string) => {
    log('info', {
      event_type: 'worker_shutdown',
      message: `received ${signal}`,
      request_id: 'worker-boot',
    });

    abortController.abort();
    await waitForInFlightDrain();

    server.close(async () => {
      await closePool();
      process.exit(0);
    });
  };

  process.on('SIGTERM', () => void shutdown('SIGTERM'));
  process.on('SIGINT', () => void shutdown('SIGINT'));
}

bootstrap().catch((error: unknown) => {
  console.error('Failed to start worker:', error);
  process.exit(1);
});
