import * as cdk from 'aws-cdk-lib';
import * as cloudtrail from 'aws-cdk-lib/aws-cloudtrail';
import * as cr from 'aws-cdk-lib/custom-resources';
import * as guardduty from 'aws-cdk-lib/aws-guardduty';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as securityhub from 'aws-cdk-lib/aws-securityhub';
import { Construct } from 'constructs';
import { TASKVAULT_CLUSTER_NAME } from './taskvault-env';

export interface ObservabilityStackProps extends cdk.StackProps {
  readonly userFilesBucket: s3.IBucket;
  readonly eksClusterName?: string;
  readonly enableInspector?: boolean;
  readonly enableGuardDuty?: boolean;
  readonly enableSecurityHub?: boolean;
}

export class ObservabilityStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: ObservabilityStackProps) {
    super(scope, id, props);

    const backendLogGroup = new logs.LogGroup(this, 'BackendLogs', {
      logGroupName: '/taskvault/backend',
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });
    const workerLogGroup = new logs.LogGroup(this, 'WorkerLogs', {
      logGroupName: '/taskvault/worker',
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });
    const frontendLogGroup = new logs.LogGroup(this, 'FrontendLogs', {
      logGroupName: '/taskvault/frontend',
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    const trailLogGroup = new logs.LogGroup(this, 'CloudTrailLogs', {
      logGroupName: '/taskvault/cloudtrail',
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    const trail = new cloudtrail.Trail(this, 'TaskvaultTrail', {
      trailName: 'taskvault-demo-trail',
      sendToCloudWatchLogs: true,
      cloudWatchLogGroup: trailLogGroup,
      includeGlobalServiceEvents: true,
      isMultiRegionTrail: false,
    });

    trail.addS3EventSelector(
      [
        {
          bucket: props.userFilesBucket,
          objectPrefix: '',
        },
      ],
      {
        readWriteType: cloudtrail.ReadWriteType.ALL,
        includeManagementEvents: false,
      },
    );

    if (props.enableInspector ?? false) {
      new cr.AwsCustomResource(this, 'EnableInspectorV2Ecr', {
        onCreate: {
          service: 'Inspector2',
          action: 'enable',
          parameters: { resourceTypes: ['ECR'] },
          physicalResourceId: cr.PhysicalResourceId.of('taskvault-inspector-ecr'),
        },
        onDelete: {
          service: 'Inspector2',
          action: 'disable',
          parameters: { resourceTypes: ['ECR'] },
        },
        policy: cr.AwsCustomResourcePolicy.fromSdkCalls({
          resources: cr.AwsCustomResourcePolicy.ANY_RESOURCE,
        }),
      });
    }

    const eksClusterName = props.eksClusterName ?? TASKVAULT_CLUSTER_NAME;

    if (props.enableGuardDuty ?? false) {
      const detector = new guardduty.CfnDetector(this, 'GuardDutyDetector', {
        enable: true,
        findingPublishingFrequency: 'FIFTEEN_MINUTES',
        dataSources: {
          kubernetes: {
            auditLogs: {
              enable: true,
            },
          },
          s3Logs: {
            enable: true,
          },
        },
      });
      cdk.Tags.of(detector).add('cnapp.demo/coverage', 'eks-s3');
      cdk.Tags.of(detector).add('cnapp.demo/eks-cluster', eksClusterName);

      new cdk.CfnOutput(this, 'GuardDutyDetectorId', {
        value: detector.attrId,
        exportName: 'TaskvaultGuardDutyDetectorId',
      });
    }

    if (props.enableSecurityHub ?? false) {
      const hub = new securityhub.CfnHub(this, 'SecurityHub', {
        enableDefaultStandards: true,
        autoEnableControls: true,
      });

      const standardsArn = `arn:${cdk.Stack.of(this).partition}:securityhub:${cdk.Stack.of(this).region}::standards/aws-foundational-security-best-practices/v/1.0.0`;
      const foundationalStandard = new securityhub.CfnStandard(this, 'AwsFoundationalStandard', {
        standardsArn,
      });
      foundationalStandard.node.addDependency(hub);

      new cdk.CfnOutput(this, 'SecurityHubArn', {
        value: hub.attrArn,
        exportName: 'TaskvaultSecurityHubArn',
      });
      new cdk.CfnOutput(this, 'SecurityHubStandardArn', {
        value: standardsArn,
      });
    }

    new cdk.CfnOutput(this, 'BackendLogGroupName', { value: backendLogGroup.logGroupName });
    new cdk.CfnOutput(this, 'WorkerLogGroupName', { value: workerLogGroup.logGroupName });
    new cdk.CfnOutput(this, 'FrontendLogGroupName', { value: frontendLogGroup.logGroupName });
    new cdk.CfnOutput(this, 'CloudTrailArn', { value: trail.trailArn });
  }
}
