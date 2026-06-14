import './db/load-env.js';

export interface AppConfig {
  nodeEnv: string;
  isTest: boolean;
  port: number;
  databaseUrl: string;
  awsRegion: string;
  awsEndpoint?: string;
  s3Bucket: string;
  sqsQueueUrl: string;
  logLevel: string;
  buildSha: string;
  jwtSecret: string;
  featureAdminReports: boolean;
  featureAdminPreview: boolean;
  featureK8sSecretList: boolean;
  inCluster: boolean;
  secretsManagerDbSecretId: string;
  secretsManagerAppSecretId: string;
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

function parseBool(value: string | undefined, defaultValue: boolean): boolean {
  if (value === undefined || value === '') {
    return defaultValue;
  }
  return value.toLowerCase() === 'true' || value === '1';
}

export function loadConfig(): AppConfig {
  const nodeEnv = process.env.NODE_ENV ?? 'development';
  const isTest = nodeEnv === 'test';

  return {
    nodeEnv,
    isTest,
    port: Number(process.env.PORT ?? 8080),
    databaseUrl: requireEnv('DATABASE_URL', isTest) || 'postgres://demo:password@localhost:5432/taskvault_test',
    awsRegion: requireEnv('AWS_REGION', isTest) || 'us-east-1',
    awsEndpoint: optionalEnv('AWS_ENDPOINT'),
    s3Bucket: requireEnv('S3_BUCKET', isTest) || 'taskvault-user-files',
    sqsQueueUrl:
      optionalEnv('SQS_QUEUE_URL') ??
      'http://localhost:4566/000000000000/taskvault-jobs',
    logLevel: process.env.LOG_LEVEL ?? 'info',
    buildSha: process.env.BUILD_SHA ?? 'unknown',
    jwtSecret: process.env.JWT_SECRET ?? 'demo-jwt-signing-secret-not-real',
    featureAdminReports: parseBool(process.env.FEATURE_ADMIN_REPORTS, true),
    featureAdminPreview: parseBool(process.env.FEATURE_ADMIN_PREVIEW, true),
    featureK8sSecretList: parseBool(process.env.FEATURE_K8S_SECRET_LIST, false),
    inCluster: process.env.USE_SECRETS_MANAGER === 'true',
    secretsManagerDbSecretId: process.env.SECRETS_MANAGER_DB_SECRET_ID ?? 'taskvault/demo/db',
    secretsManagerAppSecretId: process.env.SECRETS_MANAGER_APP_SECRET_ID ?? 'taskvault/demo/app',
  };
}

let cachedConfig: AppConfig | undefined;

export function getConfig(): AppConfig {
  if (!cachedConfig) {
    cachedConfig = loadConfig();
  }
  return cachedConfig;
}

export function setConfig(config: AppConfig): void {
  cachedConfig = config;
}

export function setJwtSecret(secret: string): void {
  getConfig().jwtSecret = secret;
}

export function setDatabaseUrl(url: string): void {
  getConfig().databaseUrl = url;
}
