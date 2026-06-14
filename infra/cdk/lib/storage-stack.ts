import * as cdk from 'aws-cdk-lib';
import * as kms from 'aws-cdk-lib/aws-kms';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as secretsmanager from 'aws-cdk-lib/aws-secretsmanager';
import * as sqs from 'aws-cdk-lib/aws-sqs';
import { Construct } from 'constructs';
import { TaskvaultKmsProps } from './taskvault-env';

export interface StorageStackProps extends cdk.StackProps, TaskvaultKmsProps {}

export class StorageStack extends cdk.Stack {
  readonly userFilesBucket: s3.Bucket;
  readonly reportsBucket: s3.Bucket;
  readonly jobsQueue: sqs.Queue;
  readonly appSecret: secretsmanager.Secret;

  constructor(scope: Construct, id: string, props: StorageStackProps) {
    super(scope, id, props);

    const encryptionKey = props.kmsKey;

    // vuln-9: versioning deliberately disabled on the crown-jewel bucket.
    this.userFilesBucket = new s3.Bucket(this, 'TaskvaultUserFiles', {
      bucketName: 'taskvault-user-files',
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.KMS,
      encryptionKey,
      versioned: false,
      enforceSSL: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });
    cdk.Tags.of(this.userFilesBucket).add('cnapp.demo/intentional-risk', 'true');
    cdk.Tags.of(this.userFilesBucket).add('cnapp.demo/risk-id', 'vuln-9');

    this.reportsBucket = new s3.Bucket(this, 'TaskvaultReports', {
      bucketName: 'taskvault-reports',
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.KMS,
      encryptionKey,
      versioned: true,
      enforceSSL: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    this.jobsQueue = new sqs.Queue(this, 'TaskvaultJobs', {
      queueName: 'taskvault-jobs',
      encryption: sqs.QueueEncryption.KMS,
      encryptionMasterKey: encryptionKey,
      enforceSSL: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    this.appSecret = new secretsmanager.Secret(this, 'TaskvaultAppSecret', {
      secretName: 'taskvault/demo/app',
      description: 'JWT signing secret for TaskVault demo',
      encryptionKey,
      generateSecretString: {
        secretStringTemplate: JSON.stringify({ purpose: 'jwt-signing' }),
        generateStringKey: 'jwtSecret',
        excludePunctuation: true,
        passwordLength: 48,
      },
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    new cdk.CfnOutput(this, 'UserFilesBucketName', {
      value: this.userFilesBucket.bucketName,
      exportName: 'TaskvaultUserFilesBucket',
    });
    new cdk.CfnOutput(this, 'ReportsBucketName', {
      value: this.reportsBucket.bucketName,
      exportName: 'TaskvaultReportsBucket',
    });
    new cdk.CfnOutput(this, 'JobsQueueUrl', {
      value: this.jobsQueue.queueUrl,
      exportName: 'TaskvaultJobsQueueUrl',
    });
    new cdk.CfnOutput(this, 'JobsQueueArn', {
      value: this.jobsQueue.queueArn,
      exportName: 'TaskvaultJobsQueueArn',
    });
    new cdk.CfnOutput(this, 'AppSecretArn', {
      value: this.appSecret.secretArn,
      exportName: 'TaskvaultAppSecretArn',
    });
  }
}
