import {
  DeleteMessageCommand,
  GetQueueAttributesCommand,
  ReceiveMessageCommand,
} from '@aws-sdk/client-sqs';
import { getConfig } from '../config.js';
import { getSqsClient } from './clients.js';

export interface JobMessage {
  jobId: string;
  fileId: string;
  type: string;
}

export function parseJobMessage(body: string): JobMessage {
  const parsed = JSON.parse(body) as JobMessage;
  if (!parsed.jobId || !parsed.type) {
    throw new Error('Invalid job message payload');
  }
  return parsed;
}

export async function checkSqsReachability(): Promise<boolean> {
  try {
    await getSqsClient().send(
      new GetQueueAttributesCommand({
        QueueUrl: getConfig().sqsQueueUrl,
        AttributeNames: ['QueueArn'],
      }),
    );
    return true;
  } catch {
    return false;
  }
}

export async function receiveOneMessage(): Promise<{
  message: JobMessage;
  receiptHandle: string;
} | null> {
  const config = getConfig();
  const response = await getSqsClient().send(
    new ReceiveMessageCommand({
      QueueUrl: config.sqsQueueUrl,
      MaxNumberOfMessages: 1,
      WaitTimeSeconds: config.sqsWaitTimeSeconds,
      VisibilityTimeout: config.sqsVisibilityTimeoutSeconds,
    }),
  );

  const raw = response.Messages?.[0];
  if (!raw?.Body || !raw.ReceiptHandle) {
    return null;
  }

  return {
    message: parseJobMessage(raw.Body),
    receiptHandle: raw.ReceiptHandle,
  };
}

export async function deleteMessage(receiptHandle: string): Promise<void> {
  await getSqsClient().send(
    new DeleteMessageCommand({
      QueueUrl: getConfig().sqsQueueUrl,
      ReceiptHandle: receiptHandle,
    }),
  );
}
