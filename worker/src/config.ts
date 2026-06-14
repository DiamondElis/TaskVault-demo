import './load-env.js';

export interface WorkerConfig {
  nodeEnv: string;
  isTest: boolean;
  port: number;
  databaseUrl: string;
  awsRegion: string;
  awsEndpoint?: string;
  s3Bucket: string;
  reportsS3Bucket: string;
  sqsQueueUrl: string;
  logLevel: string;
  buildSha: string;
  inCluster: boolean;
  secretsManagerDbSecretId: string;
  sqsVisibilityTimeoutSeconds: number;
  sqsWaitTimeSeconds: number;
}

function requireEnv(name: string, isTest: boolean): string {
  const value = process.env[name];
  if (!value && !isTest) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value ?? '';
}

function optionalEnv(name: string): string | undefined {
  const value = process.env[name];
  return value && value.length > 0 ? value : undefined;
}

export function loadConfig(): WorkerConfig {
  const nodeEnv = process.env.NODE_ENV ?? 'development';
  const isTest = nodeEnv === 'test';

  return {
    nodeEnv,
    isTest,
    port: Number(process.env.WORKER_PORT ?? 8081),
    databaseUrl: requireEnv('DATABASE_URL', isTest) || 'postgres://demo:password@localhost:5432/taskvault_test',
    awsRegion: requireEnv('AWS_REGION', isTest) || 'us-east-1',
    awsEndpoint: optionalEnv('AWS_ENDPOINT'),
    s3Bucket: requireEnv('S3_BUCKET', isTest) || 'taskvault-user-files',
    reportsS3Bucket: optionalEnv('REPORTS_S3_BUCKET') ?? 'taskvault-reports',
    sqsQueueUrl:
      optionalEnv('SQS_QUEUE_URL') ?? 'http://localhost:4566/000000000000/taskvault-jobs',
    logLevel: process.env.LOG_LEVEL ?? 'info',
    buildSha: process.env.BUILD_SHA ?? 'unknown',
    inCluster: process.env.USE_SECRETS_MANAGER === 'true',
    secretsManagerDbSecretId: process.env.SECRETS_MANAGER_DB_SECRET_ID ?? 'taskvault/demo/db',
    sqsVisibilityTimeoutSeconds: Number(process.env.SQS_VISIBILITY_TIMEOUT ?? 30),
    sqsWaitTimeSeconds: Number(process.env.SQS_WAIT_TIME_SECONDS ?? 20),
  };
}

let cachedConfig: WorkerConfig | undefined;

export function getConfig(): WorkerConfig {
  if (!cachedConfig) {
    cachedConfig = loadConfig();
  }
  return cachedConfig;
}

export function setConfig(config: WorkerConfig): void {
  cachedConfig = config;
}

export function setDatabaseUrl(url: string): void {
  getConfig().databaseUrl = url;
}
