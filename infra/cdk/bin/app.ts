#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { EcrStack } from '../lib/ecr-stack';
import { EksStack } from '../lib/eks-stack';
import { GitHubOidcRoleStack } from '../lib/github-oidc-role-stack';
import { IamStack } from '../lib/iam-stack';
import { KmsStack } from '../lib/kms-stack';
import { NetworkStack } from '../lib/network-stack';
import { ObservabilityStack } from '../lib/observability-stack';
import { RdsStack } from '../lib/rds-stack';
import { StorageStack } from '../lib/storage-stack';
import { applyTaskvaultTags, taskvaultEnvironment } from '../lib/taskvault-env';

const app = new cdk.App();
const env = taskvaultEnvironment(app);
const githubOrg: string = app.node.tryGetContext('githubOrg') ?? 'your-org';

const network = new NetworkStack(app, 'TaskvaultNetwork', {
  env,
  description: 'TaskVault VPC, subnets, and security groups',
  enableBroadNodeEgress: app.node.tryGetContext('enableBroadNodeEgress') ?? true,
});

const kms = new KmsStack(app, 'TaskvaultKms', {
  env,
  description: 'TaskVault KMS key (alias/taskvault-demo)',
});

const ecr = new EcrStack(app, 'TaskvaultEcr', {
  env,
  description: 'TaskVault ECR repositories with scan-on-push',
});

const storage = new StorageStack(app, 'TaskvaultStorage', {
  env,
  description: 'TaskVault S3 buckets, SQS queue, app secret',
  kmsKey: kms.key,
});
storage.addDependency(kms);

const rds = new RdsStack(app, 'TaskvaultRds', {
  env,
  description: 'TaskVault RDS Postgres (private, encrypted)',
  vpc: network.vpc,
  rdsSecurityGroup: network.rdsSecurityGroup,
  kmsKey: kms.key,
});
rds.addDependency(network);
rds.addDependency(kms);

const eks = new EksStack(app, 'TaskvaultEks', {
  env,
  description: 'TaskVault EKS cluster, node group, ALB controller, EBS CSI',
  vpc: network.vpc,
  nodeSecurityGroup: network.nodeSecurityGroup,
});
eks.addDependency(network);

const iam = new IamStack(app, 'TaskvaultIam', {
  env,
  description: 'TaskVault IRSA workload roles (vuln-2, vuln-6)',
  cluster: eks.cluster,
  userFilesBucket: storage.userFilesBucket,
  reportsBucket: storage.reportsBucket,
  jobsQueue: storage.jobsQueue,
  appSecret: storage.appSecret,
  dbSecret: rds.dbSecret,
});
iam.addDependency(eks);
iam.addDependency(storage);
iam.addDependency(rds);

const githubOidc = new GitHubOidcRoleStack(app, 'TaskvaultGithubOidc', {
  env,
  description: 'GitHub Actions OIDC deploy role (vuln-10)',
  githubOrg,
  clusterArn: eks.cluster.clusterArn,
});
githubOidc.addDependency(ecr);
githubOidc.addDependency(eks);

const observability = new ObservabilityStack(app, 'TaskvaultObservability', {
  env,
  description: 'TaskVault CloudWatch logs, CloudTrail, Inspector, GuardDuty, Security Hub',
  userFilesBucket: storage.userFilesBucket,
  eksClusterName: eks.cluster.clusterName,
  enableGuardDuty: app.node.tryGetContext('enableGuardDuty') ?? true,
  enableSecurityHub: app.node.tryGetContext('enableSecurityHub') ?? true,
});
observability.addDependency(storage);
observability.addDependency(ecr);
observability.addDependency(eks);

for (const stack of [network, kms, ecr, storage, rds, eks, iam, githubOidc, observability]) {
  applyTaskvaultTags(stack);
}

app.synth();
