# TaskVault CDK infrastructure

AWS CDK (TypeScript) stacks for the `taskvault-demo-prod` account in `us-east-1`.

## Stacks

| Stack | File | Purpose |
|-------|------|---------|
| TaskvaultNetwork | `lib/network-stack.ts` | VPC, subnets, ALB/RDS/node SGs (vuln-7 optional) |
| TaskvaultKms | `lib/kms-stack.ts` | `alias/taskvault-demo` |
| TaskvaultEcr | `lib/ecr-stack.ts` | ECR repos + scan-on-push |
| TaskvaultStorage | `lib/storage-stack.ts` | S3 (vuln-9), SQS, app secret |
| TaskvaultRds | `lib/rds-stack.ts` | Postgres `taskvault-db` + `taskvault/demo/db` secret |
| TaskvaultEks | `lib/eks-stack.ts` | EKS, node group, IRSA for ALB, EBS CSI (ALB Helm: `scripts/eks-install-alb-controller.sh`) |
| TaskvaultIam | `lib/iam-stack.ts` | IRSA roles (vuln-2, vuln-6) |
| TaskvaultGithubOidc | `lib/github-oidc-role-stack.ts` | GitHub deploy role (vuln-10) |
| TaskvaultObservability | `lib/observability-stack.ts` | Logs, CloudTrail, Inspector v2, GuardDuty (EKS+S3), Security Hub |

## Commands

```bash
npm install
npm run build
npm test
CDK_DEFAULT_ACCOUNT=111111111111 npx cdk synth --no-lookups   # offline synth
npx cdk deploy --all                                          # requires AWS creds
```

From repo root: `make cdk-synth` (synth + Checkov), `make cdk-deploy`.

## Context (`cdk.json`)

- `githubOrg` / `githubRepo` — GitHub OIDC trust (`repo:<org>/<repo>:*`; repo name is case-sensitive)
- `account` — AWS account ID (also set `CDK_DEFAULT_ACCOUNT` in the shell before deploy)
- `enableBroadNodeEgress` — tag node SG with vuln-7 (default `true`)
- `enableGuardDuty` — EKS audit-log + S3 protection detector (default `true`)
- `enableSecurityHub` — Security Hub + AWS Foundational standard (default `true`)
