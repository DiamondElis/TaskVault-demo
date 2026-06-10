import { GetObjectCommand, PutObjectCommand } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { getConfig } from '../config.js';
import type { FileClassification } from '../repositories/files.repo.js';
import { getS3Client } from './clients.js';

export function classificationToPrefix(classification: FileClassification): string {
  switch (classification) {
    case 'public':
      return 'uploads/public/';
    case 'private':
      return 'uploads/private/';
    case 'sensitive':
      return 'uploads/sensitive/';
    default:
      throw new Error(`Unknown classification: ${classification}`);
  }
}

export function buildObjectKey(
  classification: FileClassification,
  ownerUserId: string,
  filename: string,
): string {
  const safeName = filename.replace(/[^a-zA-Z0-9._-]/g, '_');
  return `${classificationToPrefix(classification)}${ownerUserId}/${Date.now()}-${safeName}`;
}

export async function putObject(input: {
  key: string;
  body: Buffer;
  contentType: string;
  bucket?: string;
}): Promise<{ bucket: string; key: string }> {
  const bucket = input.bucket ?? getConfig().s3Bucket;

  await getS3Client().send(
    new PutObjectCommand({
      Bucket: bucket,
      Key: input.key,
      Body: input.body,
      ContentType: input.contentType,
    }),
  );

  return { bucket, key: input.key };
}

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

export async function getPresignedDownloadUrl(
  bucket: string,
  key: string,
  expiresInSeconds = 300,
): Promise<string> {
  const command = new GetObjectCommand({ Bucket: bucket, Key: key });
  return getSignedUrl(getS3Client(), command, { expiresIn: expiresInSeconds });
}
