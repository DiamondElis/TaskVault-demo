import { randomUUID } from 'node:crypto';
import * as sqs from './aws/sqs.js';
import { audit, log } from './logger.js';
import { processJob } from './jobs/handler.js';
import { jobsProcessedTotal, jobProcessingDuration } from './metrics.js';

export interface ConsumerOptions {
  abortSignal: AbortSignal;
  onInFlightChange?: (count: number) => void;
}

let inFlight = 0;

export function getInFlightCount(): number {
  return inFlight;
}

export async function runConsumerLoop(options: ConsumerOptions): Promise<void> {
  log('info', {
    event_type: 'consumer_started',
    request_id: 'worker-boot',
  });

  while (!options.abortSignal.aborted) {
    try {
      const received = await sqs.receiveOneMessage();
      if (!received || options.abortSignal.aborted) {
        continue;
      }

      inFlight += 1;
      options.onInFlightChange?.(inFlight);
      const requestId = randomUUID();

      await audit('worker_job_started', {
        request_id: requestId,
        job_id: received.message.jobId,
        file_id: received.message.fileId,
        job_type: received.message.type,
      });

      const endTimer = jobProcessingDuration.startTimer({ job_type: received.message.type });

      try {
        await processJob(received.message, requestId);
        await sqs.deleteMessage(received.receiptHandle);
        jobsProcessedTotal.inc({ status: 'success', job_type: received.message.type });
      } catch (error) {
        jobsProcessedTotal.inc({ status: 'failed', job_type: received.message.type });
        log('error', {
          event_type: 'consumer_job_error',
          request_id: requestId,
          job_id: received.message.jobId,
          message: error instanceof Error ? error.message : 'unknown error',
        });
      } finally {
        endTimer();
        inFlight -= 1;
        options.onInFlightChange?.(inFlight);
      }
    } catch (error) {
      if (options.abortSignal.aborted) {
        break;
      }

      log('error', {
        event_type: 'consumer_poll_error',
        request_id: 'worker-boot',
        message: error instanceof Error ? error.message : 'unknown error',
      });
      await sleep(1000);
    }
  }

  log('info', {
    event_type: 'consumer_stopped',
    request_id: 'worker-boot',
  });
}

export async function waitForInFlightDrain(timeoutMs = 30_000): Promise<void> {
  const deadline = Date.now() + timeoutMs;

  while (inFlight > 0 && Date.now() < deadline) {
    await sleep(100);
  }
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
