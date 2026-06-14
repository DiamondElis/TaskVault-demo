import { S3Client } from '@aws-sdk/client-s3';
import { SecretsManagerClient } from '@aws-sdk/client-secrets-manager';
import { SQSClient } from '@aws-sdk/client-sqs';
import { getConfig } from '../config.js';

function clientConfig() {
  const config = getConfig();
  return {
    region: config.awsRegion,
    ...(config.awsEndpoint
      ? {
          endpoint: config.awsEndpoint,
          forcePathStyle: true,
          credentials: {
            accessKeyId: 'test',
            secretAccessKey: 'test',
          },
        }
      : {}),
  };
}

let s3Client: S3Client | undefined;
let sqsClient: SQSClient | undefined;
let secretsClient: SecretsManagerClient | undefined;

export function getS3Client(): S3Client {
  if (!s3Client) {
    s3Client = new S3Client(clientConfig());
  }
  return s3Client;
}

export function getSqsClient(): SQSClient {
  if (!sqsClient) {
    sqsClient = new SQSClient(clientConfig());
  }
  return sqsClient;
}

export function getSecretsManagerClient(): SecretsManagerClient {
  if (!secretsClient) {
    secretsClient = new SecretsManagerClient(clientConfig());
  }
  return secretsClient;
}
