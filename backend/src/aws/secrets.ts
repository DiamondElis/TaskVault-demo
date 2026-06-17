import { GetSecretValueCommand } from '@aws-sdk/client-secrets-manager';
import { getConfig, setDatabaseUrl, setJwtSecret } from '../config.js';
import { getSecretsManagerClient } from './clients.js';

interface DbSecretPayload {
  username?: string;
  password?: string;
  host?: string;
  port?: number | string;
  dbname?: string;
  engine?: string;
}

function buildDatabaseUrl(secret: DbSecretPayload): string {
  const username = secret.username ?? 'demo';
  const password = secret.password ?? '';
  const host = secret.host ?? 'localhost';
  const port = secret.port ?? 5432;
  const dbname = secret.dbname ?? 'taskvault';
  const base = `postgres://${encodeURIComponent(username)}:${encodeURIComponent(password)}@${host}:${port}/${dbname}`;
  if (String(host).includes('.rds.') || String(host).includes('amazonaws.com')) {
    return `${base}?sslmode=no-verify`;
  }
  return base;
}

async function readSecretString(secretId: string): Promise<string> {
  const response = await getSecretsManagerClient().send(
    new GetSecretValueCommand({ SecretId: secretId }),
  );

  if (!response.SecretString) {
    throw new Error(`Secret ${secretId} has no string value`);
  }

  return response.SecretString;
}

/**
 * vuln-6: resolves DB URL from Secrets Manager in-cluster (taskvault/demo/db).
 * Metadata/ARN usage only — secret values are never logged.
 */
export async function resolveDatabaseUrl(): Promise<string> {
  const config = getConfig();

  if (!config.inCluster) {
    return config.databaseUrl;
  }

  const raw = await readSecretString(config.secretsManagerDbSecretId);
  const parsed = JSON.parse(raw) as DbSecretPayload;
  const url = buildDatabaseUrl(parsed);
  setDatabaseUrl(url);
  return url;
}

/**
 * Loads JWT signing secret from Secrets Manager taskvault/demo/app in-cluster.
 */
export async function resolveJwtSecret(): Promise<string> {
  const config = getConfig();

  if (!config.inCluster) {
    return config.jwtSecret;
  }

  const raw = await readSecretString(config.secretsManagerAppSecretId);
  let secret = raw;

  try {
    const parsed = JSON.parse(raw) as { jwtSecret?: string; secret?: string };
    secret = parsed.jwtSecret ?? parsed.secret ?? raw;
  } catch {
    // plain string secret
  }

  setJwtSecret(secret);
  return secret;
}

export async function resolveRuntimeSecrets(): Promise<void> {
  await resolveDatabaseUrl();
  await resolveJwtSecret();
}
