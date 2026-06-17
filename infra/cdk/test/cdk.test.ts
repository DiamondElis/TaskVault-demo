import { Match, Template } from 'aws-cdk-lib/assertions';
import * as cdk from 'aws-cdk-lib';
import { KmsStack } from '../lib/kms-stack';
import { ObservabilityStack } from '../lib/observability-stack';
import { StorageStack } from '../lib/storage-stack';

test('user-files bucket has versioning disabled (vuln-9)', () => {
  const app = new cdk.App();
  const kmsStack = new KmsStack(app, 'KmsTest');
  const storage = new StorageStack(app, 'StorageTest', { kmsKey: kmsStack.key });
  const template = Template.fromStack(storage);

  template.hasResourceProperties('AWS::S3::Bucket', {
    BucketName: 'taskvault-user-files',
    VersioningConfiguration: Match.absent(),
  });
});

test('observability deploys CloudWatch and CloudTrail by default (no Inspector/GuardDuty/Security Hub)', () => {
  const app = new cdk.App();
  const kmsStack = new KmsStack(app, 'KmsTest');
  const storage = new StorageStack(app, 'StorageTest', { kmsKey: kmsStack.key });
  const observability = new ObservabilityStack(app, 'ObservabilityTest', {
    userFilesBucket: storage.userFilesBucket,
    eksClusterName: 'taskvault-eks',
  });
  const template = Template.fromStack(observability);

  template.resourceCountIs('AWS::Logs::LogGroup', 4);
  template.resourceCountIs('AWS::CloudTrail::Trail', 1);
  template.resourceCountIs('Custom::AWS', 0);
  template.resourceCountIs('AWS::GuardDuty::Detector', 0);
  template.resourceCountIs('AWS::SecurityHub::Hub', 0);
  template.resourceCountIs('AWS::SecurityHub::Standard', 0);
});

test('observability can opt in to Inspector, GuardDuty, and Security Hub (T144)', () => {
  const app = new cdk.App();
  const kmsStack = new KmsStack(app, 'KmsTest');
  const storage = new StorageStack(app, 'StorageTest', { kmsKey: kmsStack.key });
  const observability = new ObservabilityStack(app, 'ObservabilityTestOptIn', {
    userFilesBucket: storage.userFilesBucket,
    eksClusterName: 'taskvault-eks',
    enableInspector: true,
    enableGuardDuty: true,
    enableSecurityHub: true,
  });
  const template = Template.fromStack(observability);

  template.hasResourceProperties('AWS::GuardDuty::Detector', {
    Enable: true,
    DataSources: {
      Kubernetes: { AuditLogs: { Enable: true } },
      S3Logs: { Enable: true },
    },
  });
  template.resourceCountIs('AWS::SecurityHub::Hub', 1);
  template.resourceCountIs('AWS::SecurityHub::Standard', 1);
});
