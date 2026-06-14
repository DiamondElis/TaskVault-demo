import * as cdk from 'aws-cdk-lib';
import * as kms from 'aws-cdk-lib/aws-kms';
import { Construct } from 'constructs';

export const TASKVAULT_REGION = 'us-east-1';
export const TASKVAULT_CLUSTER_NAME = 'taskvault-eks';
export const TASKVAULT_NAMESPACE = 'demo-prod';

export interface TaskvaultKmsProps {
  readonly kmsKey: kms.IKey;
}

/** Resolve deploy env from CDK context or CLI defaults (synth works without live AWS creds). */
export function taskvaultEnvironment(app: cdk.App): cdk.Environment {
  return {
    account:
      app.node.tryGetContext('account') ??
      process.env.CDK_DEFAULT_ACCOUNT ??
      '111111111111',
    region:
      app.node.tryGetContext('region') ?? process.env.CDK_DEFAULT_REGION ?? TASKVAULT_REGION,
  };
}

export function applyTaskvaultTags(scope: Construct): void {
  cdk.Tags.of(scope).add('project', 'taskvault-demo');
  cdk.Tags.of(scope).add('cnapp.demo/environment', 'demo-prod');
}
