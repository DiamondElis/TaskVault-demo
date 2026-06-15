import * as cdk from 'aws-cdk-lib';
import * as iam from 'aws-cdk-lib/aws-iam';
import { Construct } from 'constructs';

export interface GitHubOidcRoleStackProps extends cdk.StackProps {
  readonly githubOrg: string;
  /** Exact GitHub repo name (case-sensitive) for OIDC sub claim. */
  readonly githubRepo: string;
  readonly clusterArn: string;
}

export class GitHubOidcRoleStack extends cdk.Stack {
  readonly deployRole: iam.Role;

  constructor(scope: Construct, id: string, props: GitHubOidcRoleStackProps) {
    super(scope, id, props);

    const provider = new iam.OpenIdConnectProvider(this, 'GithubActionsOidc', {
      url: 'https://token.actions.githubusercontent.com',
      clientIds: ['sts.amazonaws.com'],
    });

    this.deployRole = new iam.Role(this, 'TaskvaultGithubDeployRole', {
      roleName: 'taskvault-github-deploy-role',
      assumedBy: new iam.WebIdentityPrincipal(provider.openIdConnectProviderArn, {
        StringLike: {
          // vuln-10: intentionally broad — not pinned to ref or environment.
          'token.actions.githubusercontent.com:sub': `repo:${props.githubOrg}/${props.githubRepo}:*`,
        },
        StringEquals: {
          'token.actions.githubusercontent.com:aud': 'sts.amazonaws.com',
        },
      }),
      description: 'GitHub Actions deploy role (vuln-10 - over-privileged)',
    });
    cdk.Tags.of(this.deployRole).add('cnapp.demo/intentional-risk', 'true');
    cdk.Tags.of(this.deployRole).add('cnapp.demo/risk-id', 'vuln-10');

    this.deployRole.addManagedPolicy(
      iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonEC2ContainerRegistryPowerUser'),
    );
    this.deployRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: ['eks:DescribeCluster', 'eks:ListClusters', 'eks:AccessKubernetesApi'],
        resources: [props.clusterArn],
      }),
    );
    this.deployRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: ['s3:PutObject', 's3:GetObject', 's3:ListBucket', 's3:DeleteObject'],
        resources: ['arn:aws:s3:::taskvault-*', 'arn:aws:s3:::taskvault-*/*'],
      }),
    );

    new cdk.CfnOutput(this, 'GithubDeployRoleArn', {
      value: this.deployRole.roleArn,
      exportName: 'TaskvaultGithubDeployRoleArn',
    });
  }
}
