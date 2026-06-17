import { KubectlV31Layer } from '@aws-cdk/lambda-layer-kubectl-v31';
import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as eks from 'aws-cdk-lib/aws-eks';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as fs from 'fs';
import * as path from 'path';
import { Construct } from 'constructs';
import { cloudWatchObservabilityConfigurationValues } from './cloudwatch-observability-config';
import { TASKVAULT_CLUSTER_NAME } from './taskvault-env';

export interface EksStackProps extends cdk.StackProps {
  readonly vpc: ec2.IVpc;
  readonly nodeSecurityGroup: ec2.ISecurityGroup;
  /** EKS worker instance type (t3.small recommended; t3.micro fits only ~4 pods/node). */
  readonly nodeInstanceType?: string;
}

export class EksStack extends cdk.Stack {
  readonly cluster: eks.Cluster;
  /** IRSA SA for ALB controller — Helm install runs post-deploy (scripts/eks-install-alb-controller.sh). */
  readonly albControllerServiceAccount: eks.ServiceAccount;

  constructor(scope: Construct, id: string, props: EksStackProps) {
    super(scope, id, props);

    const clusterRole = new iam.Role(this, 'TaskvaultEksClusterRole', {
      roleName: 'taskvault-eks-cluster-role',
      assumedBy: new iam.ServicePrincipal('eks.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonEKSClusterPolicy'),
      ],
    });

    const nodeRole = new iam.Role(this, 'TaskvaultEksNodeRole', {
      roleName: 'taskvault-eks-node-role',
      assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonEKSWorkerNodePolicy'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonEC2ContainerRegistryReadOnly'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonEKS_CNI_Policy'),
        // Fluent Bit daemonsets ship container logs to CloudWatch (T156).
        iam.ManagedPolicy.fromAwsManagedPolicyName('CloudWatchAgentServerPolicy'),
      ],
    });

    this.cluster = new eks.Cluster(this, 'TaskvaultEks', {
      clusterName: TASKVAULT_CLUSTER_NAME,
      version: eks.KubernetesVersion.V1_31,
      vpc: props.vpc,
      vpcSubnets: [{ subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS }],
      defaultCapacity: 0,
      role: clusterRole,
      kubectlLayer: new KubectlV31Layer(this, 'KubectlLayer'),
      authenticationMode: eks.AuthenticationMode.API_AND_CONFIG_MAP,
      clusterLogging: [
        eks.ClusterLoggingTypes.API,
        eks.ClusterLoggingTypes.AUDIT,
        eks.ClusterLoggingTypes.AUTHENTICATOR,
      ],
    });

    const deployIamUser =
      (this.node.tryGetContext('deployIamUser') as string | undefined) ?? 'taskvault-deploy';
    const deployUserArn = `arn:${this.partition}:iam::${this.account}:user/${deployIamUser}`;
    const deployUser = iam.User.fromUserAttributes(this, 'DeployUser', {
      userArn: deployUserArn,
    });
    this.cluster.awsAuth.addUserMapping(deployUser, {
      username: deployIamUser,
      groups: ['system:masters'],
    });
    this.cluster.grantAccess('DeployUserClusterAdmin', deployUserArn, [
      eks.AccessPolicy.fromAccessPolicyName('AmazonEKSClusterAdminPolicy', {
        accessScopeType: eks.AccessScopeType.CLUSTER,
      }),
    ]);

    const nodeInstanceType = props?.nodeInstanceType ?? 't3.small';

    const nodeLaunchTemplate = new ec2.CfnLaunchTemplate(this, 'TaskvaultNgLaunchTemplate', {
      launchTemplateName: 'taskvault-ng-lt',
      launchTemplateData: {
        instanceType: nodeInstanceType,
        securityGroupIds: [
          props.nodeSecurityGroup.securityGroupId,
          this.cluster.clusterSecurityGroup.securityGroupId,
        ],
      },
    });

    const nodegroup = this.cluster.addNodegroupCapacity('TaskvaultNg', {
      nodegroupName: 'taskvault-ng',
      minSize: 3,
      maxSize: 3,
      desiredSize: 3,
      subnets: { subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS },
      nodeRole,
      launchTemplateSpec: {
        id: nodeLaunchTemplate.ref,
        version: nodeLaunchTemplate.attrLatestVersionNumber,
      },
    });
    const cfnNodegroup = nodegroup.node.defaultChild as eks.CfnNodegroup;

    // IRSA only — Helm runs outside CloudFormation to avoid stuck-release rollbacks.
    this.albControllerServiceAccount = new eks.ServiceAccount(this, 'AlbControllerSa', {
      cluster: this.cluster,
      name: 'aws-load-balancer-controller',
      namespace: 'kube-system',
    });
    this.albControllerServiceAccount.node.addDependency(cfnNodegroup);
    this.attachAlbControllerPolicy(this.albControllerServiceAccount);

    const ebsCsi = new eks.CfnAddon(this, 'EbsCsiDriver', {
      addonName: 'aws-ebs-csi-driver',
      clusterName: this.cluster.clusterName,
      resolveConflicts: 'OVERWRITE',
    });
    ebsCsi.addDependency(cfnNodegroup);

    // T156 — ship pod logs to /taskvault/* via Fluent Bit (observability add-on).
    const cloudWatchObs = new eks.CfnAddon(this, 'CloudWatchObservability', {
      addonName: 'amazon-cloudwatch-observability',
      clusterName: this.cluster.clusterName,
      resolveConflicts: 'OVERWRITE',
      configurationValues: cloudWatchObservabilityConfigurationValues(),
    });
    cloudWatchObs.addDependency(cfnNodegroup);

    new cdk.CfnOutput(this, 'ClusterName', {
      value: this.cluster.clusterName,
      exportName: 'TaskvaultEksClusterName',
    });
    new cdk.CfnOutput(this, 'ClusterOidcIssuer', {
      value: this.cluster.clusterOpenIdConnectIssuer,
      exportName: 'TaskvaultEksOidcIssuer',
    });
    new cdk.CfnOutput(this, 'ClusterArn', {
      value: this.cluster.clusterArn,
      exportName: 'TaskvaultEksClusterArn',
    });
    new cdk.CfnOutput(this, 'AlbControllerRoleArn', {
      value: this.albControllerServiceAccount.role.roleArn,
      description: 'IRSA role for aws-load-balancer-controller (Helm installed post-deploy)',
    });
  }

  private attachAlbControllerPolicy(serviceAccount: eks.ServiceAccount): void {
    const policyPath = path.join(__dirname, 'alb-controller-iam-policy.json');
    const policy = JSON.parse(fs.readFileSync(policyPath, 'utf8')) as {
      Statement: Record<string, unknown>[];
    };
    const partition = cdk.Stack.of(this).partition;
    const region = cdk.Stack.of(this).region;
    const rewriteResources = (resources: unknown): unknown => {
      if (!resources) return resources;
      const rewriteOne = (value: string) => {
        if (!value.startsWith('arn:')) return value;
        const parts = value.split(':');
        // arn:partition:service:region:account:resource — only substitute region wildcard.
        if (parts.length >= 5 && parts[3] === '*') {
          parts[3] = region;
          return parts.join(':');
        }
        return value.replace('arn:aws:', `arn:${partition}:`);
      };
      if (Array.isArray(resources)) return resources.map(rewriteOne);
      if (typeof resources === 'string') return rewriteOne(resources);
      return resources;
    };
    for (const statement of policy.Statement) {
      serviceAccount.addToPrincipalPolicy(
        iam.PolicyStatement.fromJson({
          ...statement,
          Resource: rewriteResources(statement.Resource),
        }),
      );
    }
  }
}
