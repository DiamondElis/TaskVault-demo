import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as rds from 'aws-cdk-lib/aws-rds';
import * as secretsmanager from 'aws-cdk-lib/aws-secretsmanager';
import { Construct } from 'constructs';
import { TaskvaultKmsProps } from './taskvault-env';

export interface RdsStackProps extends cdk.StackProps, TaskvaultKmsProps {
  readonly vpc: ec2.IVpc;
  readonly rdsSecurityGroup: ec2.ISecurityGroup;
}

export class RdsStack extends cdk.Stack {
  readonly database: rds.DatabaseInstance;
  readonly dbSecret: secretsmanager.Secret;

  constructor(scope: Construct, id: string, props: RdsStackProps) {
    super(scope, id, props);

    this.dbSecret = new secretsmanager.Secret(this, 'TaskvaultDbSecret', {
      secretName: 'taskvault/demo/db',
      description: 'RDS credentials for taskvault-db',
      encryptionKey: props.kmsKey,
      generateSecretString: {
        secretStringTemplate: JSON.stringify({
          username: 'taskvault_admin',
          engine: 'postgres',
          dbname: 'taskvault',
        }),
        generateStringKey: 'password',
        excludePunctuation: true,
        passwordLength: 32,
      },
    });

    this.database = new rds.DatabaseInstance(this, 'TaskvaultDb', {
      instanceIdentifier: 'taskvault-db',
      engine: rds.DatabaseInstanceEngine.postgres({
        version: rds.PostgresEngineVersion.VER_16,
      }),
      instanceType: ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.MICRO),
      vpc: props.vpc,
      vpcSubnets: { subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS },
      securityGroups: [props.rdsSecurityGroup],
      credentials: rds.Credentials.fromSecret(this.dbSecret),
      // Omit databaseName: adding it to an existing custom-named instance forces replacement,
      // which CloudFormation blocks. DB name is in the Secrets Manager template (dbname: taskvault).
      allocatedStorage: 20,
      storageEncrypted: true,
      storageEncryptionKey: props.kmsKey,
      copyTagsToSnapshot: true,
      publiclyAccessible: false,
      multiAz: false,
      deletionProtection: false,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      backupRetention: cdk.Duration.days(1),
    });

    new cdk.CfnOutput(this, 'DbEndpoint', {
      value: this.database.dbInstanceEndpointAddress,
      exportName: 'TaskvaultDbEndpoint',
    });
    new cdk.CfnOutput(this, 'DbSecretArn', {
      value: this.dbSecret.secretArn,
      exportName: 'TaskvaultDbSecretArn',
    });
  }
}
