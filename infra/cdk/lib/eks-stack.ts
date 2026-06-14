import { KubectlV31Layer } from '@aws-cdk/lambda-layer-kubectl-v31';
import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as eks from 'aws-cdk-lib/aws-eks';
import * as iam from 'aws-cdk-lib/aws-iam';
import { Construct } from 'constructs';
import { TASKVAULT_CLUSTER_NAME } from './taskvault-env';

export interface EksStackProps extends cdk.StackProps {
  readonly vpc: ec2.IVpc;
  readonly nodeSecurityGroup: ec2.ISecurityGroup;
}

export class EksStack extends cdk.Stack {
  readonly cluster: eks.Cluster;

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
      clusterLogging: [
        eks.ClusterLoggingTypes.API,
        eks.ClusterLoggingTypes.AUDIT,
        eks.ClusterLoggingTypes.AUTHENTICATOR,
      ],
    });

    const nodeLaunchTemplate = new ec2.CfnLaunchTemplate(this, 'TaskvaultNgLaunchTemplate', {
      launchTemplateName: 'taskvault-ng-lt',
      launchTemplateData: {
        instanceType: 't3.medium',
        securityGroupIds: [
          props.nodeSecurityGroup.securityGroupId,
          this.cluster.clusterSecurityGroup.securityGroupId,
        ],
      },
    });

    this.cluster.addNodegroupCapacity('TaskvaultNg', {
      nodegroupName: 'taskvault-ng',
      minSize: 2,
      maxSize: 2,
      desiredSize: 2,
      subnets: { subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS },
      nodeRole,
      launchTemplateSpec: {
        id: nodeLaunchTemplate.ref,
        version: nodeLaunchTemplate.attrLatestVersionNumber,
      },
    });

    new eks.AlbController(this, 'AlbController', {
      cluster: this.cluster,
      version: eks.AlbControllerVersion.V2_8_2,
    });

    new eks.CfnAddon(this, 'EbsCsiDriver', {
      addonName: 'aws-ebs-csi-driver',
      clusterName: this.cluster.clusterName,
      resolveConflicts: 'OVERWRITE',
    });

    // T156 — ship pod logs to CloudWatch (Fluent Bit via observability add-on).
    new eks.CfnAddon(this, 'CloudWatchObservability', {
      addonName: 'amazon-cloudwatch-observability',
      clusterName: this.cluster.clusterName,
      resolveConflicts: 'OVERWRITE',
    });

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
  }
}
