import { createApp } from './app.js';
import { resolveRuntimeSecrets } from './aws/secrets.js';
import { getConfig, loadConfig } from './config.js';
import { initPool, closePool } from './db/pool.js';
import { log } from './logger.js';

async function bootstrap(): Promise<void> {
  loadConfig();
  await resolveRuntimeSecrets();
  initPool(getConfig().databaseUrl);

  const app = createApp();
  const config = getConfig();
  const server = app.listen(config.port, () => {
    log('info', {
      event_type: 'server_started',
      message: `backend-api listening on :${config.port}`,
      request_id: 'boot',
    });
  });

  const shutdown = async (signal: string) => {
    log('info', {
      event_type: 'server_shutdown',
      message: `received ${signal}`,
      request_id: 'boot',
    });

    server.close(async () => {
      await closePool();
      process.exit(0);
    });
  };

  process.on('SIGTERM', () => void shutdown('SIGTERM'));
  process.on('SIGINT', () => void shutdown('SIGINT'));
}

bootstrap().catch((error: unknown) => {
  console.error('Failed to start backend-api:', error);
  process.exit(1);
});
