import * as cdk from 'aws-cdk-lib';
import * as kms from 'aws-cdk-lib/aws-kms';
import { Construct } from 'constructs';

export class KmsStack extends cdk.Stack {
  readonly key: kms.Key;

  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    this.key = new kms.Key(this, 'TaskvaultDemoKey', {
      alias: 'alias/taskvault-demo',
      description: 'TaskVault demo — encrypts S3, RDS, Secrets Manager, SQS',
      enableKeyRotation: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    new cdk.CfnOutput(this, 'KmsKeyArn', {
      value: this.key.keyArn,
      exportName: 'TaskvaultKmsKeyArn',
    });
    new cdk.CfnOutput(this, 'KmsKeyId', {
      value: this.key.keyId,
      exportName: 'TaskvaultKmsKeyId',
    });
  }
}
