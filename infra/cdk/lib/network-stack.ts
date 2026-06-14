import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import { Construct } from 'constructs';
import { TASKVAULT_CLUSTER_NAME } from './taskvault-env';

export interface NetworkStackProps extends cdk.StackProps {
  readonly enableBroadNodeEgress?: boolean;
}

export class NetworkStack extends cdk.Stack {
  readonly vpc: ec2.Vpc;
  readonly albSecurityGroup: ec2.SecurityGroup;
  readonly rdsSecurityGroup: ec2.SecurityGroup;
  readonly nodeSecurityGroup: ec2.SecurityGroup;

  constructor(scope: Construct, id: string, props?: NetworkStackProps) {
    super(scope, id, props);

    this.vpc = new ec2.Vpc(this, 'TaskvaultVpc', {
      vpcName: 'taskvault-vpc',
      ipAddresses: ec2.IpAddresses.cidr('10.0.0.0/16'),
      maxAzs: 2,
      natGateways: 1,
      subnetConfiguration: [
        {
          name: 'taskvault-public',
          subnetType: ec2.SubnetType.PUBLIC,
          cidrMask: 20,
        },
        {
          name: 'taskvault-private',
          subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
          cidrMask: 20,
        },
      ],
    });

    this.tagSubnetsForEksAlb();

    this.albSecurityGroup = new ec2.SecurityGroup(this, 'TaskvaultAlbSg', {
      vpc: this.vpc,
      securityGroupName: 'taskvault-alb-sg',
      description: 'Internet-facing ALB (vuln-1 surface)',
      allowAllOutbound: true,
    });
    this.albSecurityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(80),
      'HTTP from internet',
    );
    this.albSecurityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(443),
      'HTTPS from internet',
    );

    const broadNodeEgress = props?.enableBroadNodeEgress ?? true;
    this.nodeSecurityGroup = new ec2.SecurityGroup(this, 'TaskvaultNodeSg', {
      vpc: this.vpc,
      securityGroupName: 'taskvault-node-sg',
      description: broadNodeEgress
        ? 'EKS worker nodes — broad egress 0.0.0.0/0 (optional vuln-7 AWS layer)'
        : 'EKS worker nodes',
      allowAllOutbound: broadNodeEgress,
    });

    if (broadNodeEgress) {
      cdk.Tags.of(this.nodeSecurityGroup).add('cnapp.demo/intentional-risk', 'true');
      cdk.Tags.of(this.nodeSecurityGroup).add('cnapp.demo/risk-id', 'vuln-7');
    }

    this.rdsSecurityGroup = new ec2.SecurityGroup(this, 'TaskvaultRdsSg', {
      vpc: this.vpc,
      securityGroupName: 'taskvault-rds-sg',
      description: 'Postgres — nodes only',
      allowAllOutbound: false,
    });
    this.rdsSecurityGroup.addIngressRule(
      this.nodeSecurityGroup,
      ec2.Port.tcp(5432),
      'Postgres from EKS nodes',
    );

    new cdk.CfnOutput(this, 'VpcId', { value: this.vpc.vpcId, exportName: 'TaskvaultVpcId' });
    new cdk.CfnOutput(this, 'AlbSecurityGroupId', {
      value: this.albSecurityGroup.securityGroupId,
      exportName: 'TaskvaultAlbSgId',
    });
    new cdk.CfnOutput(this, 'RdsSecurityGroupId', {
      value: this.rdsSecurityGroup.securityGroupId,
      exportName: 'TaskvaultRdsSgId',
    });
    new cdk.CfnOutput(this, 'NodeSecurityGroupId', {
      value: this.nodeSecurityGroup.securityGroupId,
      exportName: 'TaskvaultNodeSgId',
    });
  }

  private tagSubnetsForEksAlb(): void {
    const clusterTag = `kubernetes.io/cluster/${TASKVAULT_CLUSTER_NAME}`;
    this.vpc.publicSubnets.forEach((subnet, index) => {
      cdk.Tags.of(subnet).add('Name', `taskvault-public-${String.fromCharCode(97 + index)}`);
      cdk.Tags.of(subnet).add('kubernetes.io/role/elb', '1');
      cdk.Tags.of(subnet).add(clusterTag, 'shared');
    });
    this.vpc.privateSubnets.forEach((subnet, index) => {
      cdk.Tags.of(subnet).add('Name', `taskvault-private-${String.fromCharCode(97 + index)}`);
      cdk.Tags.of(subnet).add('kubernetes.io/role/internal-elb', '1');
      cdk.Tags.of(subnet).add(clusterTag, 'shared');
    });
  }
}
