import { SendMessageCommand } from '@aws-sdk/client-sqs';
import { getConfig } from '../config.js';
import { getSqsClient } from './clients.js';

export interface JobMessage {
  jobId: string;
  fileId: string;
  type: string;
}

export async function sendJob(message: JobMessage): Promise<void> {
  const queueUrl = getConfig().sqsQueueUrl;

  await getSqsClient().send(
    new SendMessageCommand({
      QueueUrl: queueUrl,
      MessageBody: JSON.stringify(message),
    }),
  );
}
