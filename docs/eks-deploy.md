# EKS bootstrap & deploy (M9)

Deploy TaskVault to `taskvault-eks` in `taskvault-demo-prod` (`us-east-1`).

## Prerequisites

- AWS CLI configured for the demo account
- `kubectl`, `docker`, `make`
- CDK bootstrap: `cd infra/cdk && npx cdk bootstrap`

## Phased deploy

```bash
# T146 — VPC, KMS, ECR, S3, SQS, RDS, observability
make cdk-deploy-foundation

# T147 — EKS cluster + kubeconfig
make cdk-deploy-eks

# T148 / T150 — nodes, add-ons, OIDC, ALB controller
make eks-verify

# T149 — IRSA roles + GitHub OIDC
make cdk-deploy-iam

# T153 — push :bootstrap images to ECR
make ecr-push-bootstrap

# T151–T154 — apply overlays/eks (IRSA ARNs + ECR refs substituted from stack outputs)
make k8s-deploy

# T155 / T156 — evidence
make eks-verify-alb
make eks-verify-logs
```

Or run all CDK phases: `make cdk-deploy` (foundation → EKS → IAM).

## Stack outputs used

| Output | Stack | Used for |
|--------|-------|----------|
| `BackendRoleArn` | TaskvaultIam | `backend-sa` IRSA (vuln-6) |
| `WorkerRoleArn` | TaskvaultIam | `worker-sa` IRSA |
| `FrontendRepoUri` / `BackendRepoUri` / `WorkerRepoUri` | TaskvaultEcr | ECR push + kustomize images |
| `JobsQueueUrl` | TaskvaultStorage | backend/worker config |

## Image tags

Bootstrap push uses `:bootstrap` and `:bootstrap-migrator` on the backend repo (T152–T153). CI replaces these in M12.

## Log flow (T156)

- CDK creates `/taskvault/backend`, `/taskvault/worker`, `/taskvault/frontend` log groups
- EKS `amazon-cloudwatch-observability` add-on ships container logs to CloudWatch
- `make eks-verify-logs` checks log groups and searches for audit JSON lines

## Deploy & seed (M10)

After `make k8s-deploy` (which runs db-migrator with `SKIP_DEMO_SEED=true`):

```bash
# T157 — re-run migrator + verify RDS schema via IRSA/Secrets Manager
make eks-run-db-migrator

# T158/T159 — demo users, tasks, file rows, jobs + sensitive S3 fixtures (vuln-9)
make eks-seed-demo
# or: SEED_TARGET=eks make seed-demo

# T160–T164 — end-to-end + evidence
make smoke-eks
make eks-verify-irsa-s3
make eks-verify-worker-flow
make eks-verify-audit-coverage
make eks-verify-report-cronjob
```

Or run the full M10 chain:

```bash
make eks-deploy-seed-verify
```

### M10 task map

| Task | Target | Evidence |
|------|--------|----------|
| T157 | `make eks-run-db-migrator` | `artifacts/sample/eks-db-migrator-*.txt` |
| T158/T159 | `make eks-seed-demo` | sensitive objects under `uploads/sensitive/` |
| T160 | `make smoke-eks` | `artifacts/sample/eks-e2e-*.txt` |
| T161 | `make eks-verify-irsa-s3` | CloudTrail AssumeRoleWithWebIdentity + no static keys |
| T162 | `make eks-verify-worker-flow` | `worker_job_*` audit events |
| T163 | `make eks-verify-audit-coverage` | all §2 `event_type` values |
| T164 | `make eks-verify-report-cronjob` | objects in `taskvault-reports/reports/admin/` |
