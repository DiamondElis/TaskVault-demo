import * as cdk from 'aws-cdk-lib';
import * as ecr from 'aws-cdk-lib/aws-ecr';
import { Construct } from 'constructs';

export class EcrStack extends cdk.Stack {
  readonly frontendRepository: ecr.Repository;
  readonly backendRepository: ecr.Repository;
  readonly workerRepository: ecr.Repository;

  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    const repoProps: ecr.RepositoryProps = {
      imageScanOnPush: true,
      imageTagMutability: ecr.TagMutability.MUTABLE,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      emptyOnDelete: true,
    };

    this.frontendRepository = new ecr.Repository(this, 'TaskvaultFrontend', {
      ...repoProps,
      repositoryName: 'taskvault-frontend',
    });
    this.backendRepository = new ecr.Repository(this, 'TaskvaultBackend', {
      ...repoProps,
      repositoryName: 'taskvault-backend',
    });
    this.workerRepository = new ecr.Repository(this, 'TaskvaultWorker', {
      ...repoProps,
      repositoryName: 'taskvault-worker',
    });

    new cdk.CfnOutput(this, 'FrontendRepoUri', {
      value: this.frontendRepository.repositoryUri,
      exportName: 'TaskvaultFrontendRepoUri',
    });
    new cdk.CfnOutput(this, 'BackendRepoUri', {
      value: this.backendRepository.repositoryUri,
      exportName: 'TaskvaultBackendRepoUri',
    });
    new cdk.CfnOutput(this, 'WorkerRepoUri', {
      value: this.workerRepository.repositoryUri,
      exportName: 'TaskvaultWorkerRepoUri',
    });
  }
}
