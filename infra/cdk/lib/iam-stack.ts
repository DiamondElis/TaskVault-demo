import * as cdk from 'aws-cdk-lib';
import { CfnJson } from 'aws-cdk-lib';
import * as eks from 'aws-cdk-lib/aws-eks';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as secretsmanager from 'aws-cdk-lib/aws-secretsmanager';
import * as sqs from 'aws-cdk-lib/aws-sqs';
import { Construct } from 'constructs';
import { TASKVAULT_NAMESPACE } from './taskvault-env';

export interface IamStackProps extends cdk.StackProps {
  readonly cluster: eks.Cluster;
  readonly userFilesBucket: s3.IBucket;
  readonly reportsBucket: s3.IBucket;
  readonly jobsQueue: sqs.IQueue;
  readonly appSecret: secretsmanager.ISecret;
  readonly dbSecret: secretsmanager.ISecret;
}

export class IamStack extends cdk.Stack {
  readonly backendRole: iam.Role;
  readonly workerRole: iam.Role;

  constructor(scope: Construct, id: string, props: IamStackProps) {
    super(scope, id, props);

    const oidcProvider = props.cluster.openIdConnectProvider;
    if (!oidcProvider) {
      throw new Error('EKS cluster OIDC provider is required for IRSA');
    }

    const backendTrust = new CfnJson(this, 'BackendSaTrustCondition', {
      value: {
        [`${props.cluster.clusterOpenIdConnectIssuer}:aud`]: 'sts.amazonaws.com',
        [`${props.cluster.clusterOpenIdConnectIssuer}:sub`]: `system:serviceaccount:${TASKVAULT_NAMESPACE}:backend-sa`,
      },
    });

    this.backendRole = new iam.Role(this, 'TaskvaultBackendRole', {
      roleName: 'taskvault-backend-role',
      assumedBy: new iam.FederatedPrincipal(
        oidcProvider.openIdConnectProviderArn,
        {
          StringEquals: backendTrust,
        },
        'sts:AssumeRoleWithWebIdentity',
      ),
      description: 'IRSA role for backend-api (vuln-2, vuln-6)',
    });
    cdk.Tags.of(this.backendRole).add('cnapp.demo/intentional-risk', 'true');
    cdk.Tags.of(this.backendRole).add('cnapp.demo/risk-id', 'vuln-2');

    this.backendRole.addToPolicy(
      new iam.PolicyStatement({
        sid: 'Vuln2BroadS3Access',
        effect: iam.Effect.ALLOW,
        actions: ['s3:*'],
        resources: ['arn:aws:s3:::taskvault-*', 'arn:aws:s3:::taskvault-*/*'],
      }),
    );
    this.backendRole.addToPolicy(
      new iam.PolicyStatement({
        sid: 'Vuln6SecretsManagerRead',
        effect: iam.Effect.ALLOW,
        actions: ['secretsmanager:GetSecretValue'],
        resources: [
          props.appSecret.secretArn,
          props.dbSecret.secretArn,
          `arn:aws:secretsmanager:${cdk.Stack.of(this).region}:${cdk.Stack.of(this).account}:secret:taskvault/demo/*`,
        ],
      }),
    );
    props.jobsQueue.grantSendMessages(this.backendRole);

    const workerTrust = new CfnJson(this, 'WorkerSaTrustCondition', {
      value: {
        [`${props.cluster.clusterOpenIdConnectIssuer}:aud`]: 'sts.amazonaws.com',
        [`${props.cluster.clusterOpenIdConnectIssuer}:sub`]: `system:serviceaccount:${TASKVAULT_NAMESPACE}:worker-sa`,
      },
    });

    this.workerRole = new iam.Role(this, 'TaskvaultWorkerRole', {
      roleName: 'taskvault-worker-role',
      assumedBy: new iam.FederatedPrincipal(
        oidcProvider.openIdConnectProviderArn,
        {
          StringEquals: workerTrust,
        },
        'sts:AssumeRoleWithWebIdentity',
      ),
      description: 'IRSA role for worker (scoped contrast)',
    });

    props.jobsQueue.grantConsumeMessages(this.workerRole);
    props.userFilesBucket.grantReadWrite(this.workerRole, 'uploads/*');
    props.reportsBucket.grantReadWrite(this.workerRole, 'reports/*');

    new cdk.CfnOutput(this, 'BackendRoleArn', {
      value: this.backendRole.roleArn,
      exportName: 'TaskvaultBackendRoleArn',
    });
    new cdk.CfnOutput(this, 'WorkerRoleArn', {
      value: this.workerRole.roleArn,
      exportName: 'TaskvaultWorkerRoleArn',
    });
  }
}
