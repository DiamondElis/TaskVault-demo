# AWS deploy profile (CDK / EKS)

The `cnapp-local-dev` IAM user is scoped for read/scanner work and **cannot** run `cdk bootstrap` or `make cdk-deploy`. Use a separate **`taskvault-deploy`** profile with admin rights in the dedicated demo account (`840315891380`).

## Option A — Script (admin credentials required once)

From a shell where you have **IAM admin** (root user, account admin, or CloudShell):

```bash
# If admin keys are in a separate profile:
ADMIN_AWS_PROFILE=<your-admin-profile> ./scripts/aws-create-deploy-user.sh

# Or one-off env vars (Console → IAM → create keys for an admin user):
AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=... ./scripts/aws-create-deploy-user.sh
```

This creates:

| Item | Value |
|------|-------|
| IAM user | `taskvault-deploy` |
| Policy | `AdministratorAccess` (required for CDK IAM/OIDC/IRSA stacks) |
| CLI profile | `taskvault-deploy` in `~/.aws/credentials` |

> **Why not PowerUser?** `PowerUserAccess` blocks IAM role/policy creation. TaskVault CDK deploys EKS IRSA roles, GitHub OIDC, and workload IAM — all need `iam:*`.

## Option B — AWS Console (manual)

1. Sign in as **account root** or an IAM admin.
2. **IAM → Users → Create user** `taskvault-deploy` → programmatic access.
3. **Attach policy** `AdministratorAccess` (demo sandbox only).
4. Save access key + secret.
5. Configure CLI:

```bash
aws configure --profile taskvault-deploy
# region: us-east-1
# output: json
```

## Use the deploy profile

```bash
export AWS_PROFILE=taskvault-deploy
export CDK_DEFAULT_ACCOUNT=840315891380
export CDK_DEFAULT_REGION=us-east-1

aws sts get-caller-identity   # should show user/taskvault-deploy

cd infra/cdk && npx cdk bootstrap
cd ../.. && make cdk-deploy
```

Set `githubOrg` in `infra/cdk/cdk.json` to `DiamondElis` before deploying the OIDC stack (repo: `DiamondElis/TaskVault-demo`).

## GitHub Actions

After `TaskvaultGithubOidc` is deployed, add repository **Variable**:

```
AWS_OIDC_ROLE_ARN = arn:aws:iam::840315891380:role/taskvault-github-deploy-role
```

CI uses OIDC (no long-lived keys in GitHub). The `taskvault-deploy` profile is for **local** bootstrap and first deploy only.

## Security notes

- Use `taskvault-deploy` only for infra; keep `cnapp-local-dev` as default for scanners.
- Never commit access keys or add them to `.env`.
- Rotate keys: `ROTATE_DEPLOY_KEY=true ./scripts/aws-create-deploy-user.sh`, then deactivate old keys in IAM.
