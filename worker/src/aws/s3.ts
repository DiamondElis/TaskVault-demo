import { GetObjectCommand, PutObjectCommand } from '@aws-sdk/client-s3';
import { getConfig } from '../config.js';
import { getS3Client } from './clients.js';

export async function getObject(bucket: string, key: string): Promise<Buffer> {
  const response = await getS3Client().send(
    new GetObjectCommand({ Bucket: bucket, Key: key }),
  );

  const bytes = await response.Body?.transformToByteArray();
  if (!bytes) {
    throw new Error('Empty S3 object body');
  }

  return Buffer.from(bytes);
}

export async function putObject(input: {
  bucket?: string;
  key: string;
  body: Buffer;
  contentType?: string;
}): Promise<{ bucket: string; key: string }> {
  const bucket = input.bucket ?? getConfig().s3Bucket;

  await getS3Client().send(
    new PutObjectCommand({
      Bucket: bucket,
      Key: input.key,
      Body: input.body,
      ContentType: input.contentType ?? 'application/json',
    }),
  );

  return { bucket, key: input.key };
}
