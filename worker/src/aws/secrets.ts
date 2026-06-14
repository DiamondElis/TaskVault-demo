import { GetSecretValueCommand } from '@aws-sdk/client-secrets-manager';
import { getConfig, setDatabaseUrl } from '../config.js';
import { getSecretsManagerClient } from './clients.js';

interface DbSecretPayload {
  username?: string;
  password?: string;
  host?: string;
  port?: number | string;
  dbname?: string;
}

function buildDatabaseUrl(secret: DbSecretPayload): string {
  const username = secret.username ?? 'demo';
  const password = secret.password ?? '';
  const host = secret.host ?? 'localhost';
  const port = secret.port ?? 5432;
  const dbname = secret.dbname ?? 'taskvault';
  return `postgres://${encodeURIComponent(username)}:${encodeURIComponent(password)}@${host}:${port}/${dbname}`;
}

export async function resolveDatabaseUrl(): Promise<string> {
  const config = getConfig();
  if (!config.inCluster) {
    return config.databaseUrl;
  }

  const response = await getSecretsManagerClient().send(
    new GetSecretValueCommand({ SecretId: config.secretsManagerDbSecretId }),
  );

  if (!response.SecretString) {
    throw new Error(`Secret ${config.secretsManagerDbSecretId} has no string value`);
  }

  const url = buildDatabaseUrl(JSON.parse(response.SecretString) as DbSecretPayload);
  setDatabaseUrl(url);
  return url;
}

export async function resolveRuntimeSecrets(): Promise<void> {
  await resolveDatabaseUrl();
}
