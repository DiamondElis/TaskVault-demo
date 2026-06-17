# Cleanup

Full teardown procedures for the TaskVault demo lab. Run these when evaluation is complete to avoid cost and lingering exposure.

**Account:** dedicated `taskvault-demo-prod` only — never run against production accounts.

---

## 1. Quick destroy (recommended)

```bash
make destroy
```

This target runs CDK destroy across all TaskVault stacks in dependency-safe order and removes ECR images. Requires AWS credentials for `taskvault-deploy`.

---

## 2. Manual teardown order

If `make destroy` is unavailable or a stack is stuck, delete in this order:

### Step 1 — Kubernetes workloads

```bash
kubectl delete namespace demo-prod --ignore-not-found
# Wait for ALB / target groups to detach (can take several minutes)
```

### Step 2 — EKS add-ons (if orphaned)

```bash
# ALB controller (if installed via Helm outside CDK retention)
helm uninstall aws-load-balancer-controller -n kube-system 2>/dev/null || true
```

### Step 3 — CDK stacks (reverse dependency)

```bash
cd infra/cdk
npx cdk destroy TaskvaultIam --force
npx cdk destroy TaskvaultGithubOidc --force
npx cdk destroy TaskvaultEks --force
npx cdk destroy TaskvaultObservability --force
npx cdk destroy TaskvaultRds --force
npx cdk destroy TaskvaultStorage --force
npx cdk destroy TaskvaultEcr --force
npx cdk destroy TaskvaultKms --force
npx cdk destroy TaskvaultNetwork --force
```

Or all at once: `npx cdk destroy --all --force`

**Note:** RDS deletion protection is off for demo; final snapshot behavior depends on stack settings. S3 buckets may require emptying before deletion if `autoDeleteObjects` is not enabled.

### Step 4 — ECR images

```bash
AWS_PROFILE=taskvault-deploy aws ecr batch-delete-image \
  --repository-name taskvault-backend \
  --image-ids imageTag=bootstrap 2>/dev/null || true
# Repeat for taskvault-frontend, taskvault-worker
```

### Step 5 — Local resources

```bash
make kind-down
make local-down
docker rmi taskvault-backend:local taskvault-frontend:local taskvault-worker:local 2>/dev/null || true
```

---

## 3. Stuck stack recovery

| State | Action |
|---|---|
| `UPDATE_ROLLBACK_COMPLETE` | Fix template issue, redeploy, or delete stack |
| `DELETE_FAILED` (S3 non-empty) | Empty bucket in console, retry delete |
| `DELETE_FAILED` (ENI / ALB) | Ensure `demo-prod` namespace and ALB are gone; wait 15 min |
| EKS `CREATE_IN_PROGRESS` stuck | Do not start parallel deploys; wait or delete cluster via console |
| RDS snapshot delete slow | Normal — wait for `DELETE_COMPLETE` |

See [eks-deploy.md](eks-deploy.md) for RDS `databaseName` rollback caveat.

---

## 4. GitHub / CI cleanup

- Remove or disable `AWS_OIDC_ROLE_ARN` repository variable if decommissioning
- Optionally delete `taskvault-github-deploy-role` IAM role after CDK destroy
- GitHub Actions secrets: no real secrets should exist; verify with `make export-evidence` gitleaks output

---

## 5. Evidence retention

Generated artifacts in `artifacts/sample/` can be kept for CNAPP validation **after** teardown — that is the point of `make export-evidence` and `expected-*.json`.

Do not commit timestamped evidence files unless intentionally archiving a demo run.

---

## 6. Account hygiene checklist

After destroy, confirm in AWS console:

- [ ] No EKS clusters named `taskvault-eks`
- [ ] No RDS instance `taskvault-db`
- [ ] No S3 buckets `taskvault-user-files`, `taskvault-reports`
- [ ] No IAM roles `taskvault-backend-role`, `taskvault-worker-role`, `taskvault-github-deploy-role`
- [ ] No VPC `taskvault-vpc` (or default empty VPC only)
- [ ] CloudTrail / log groups removed or empty (Observability stack deleted)
- [ ] ECR repositories empty or deleted
- [ ] No unexpected running EC2 (orphaned nodes)

---

## 7. Cost notes

Largest cost drivers while running:

- EKS control plane (~$0.10/hr)
- NAT gateway (~$0.045/hr + data)
- RDS db.t3.micro (Free Tier eligible)
- ALB (~$0.0225/hr)

Destroy promptly after demos. Use `t3.micro` node type in Free Tier accounts (`infra/cdk/cdk.json`).

---

## Related

- [runbook.md](runbook.md) — deploy and validate
- [aws-deploy-profile.md](aws-deploy-profile.md) — IAM user setup
- [intentional-risks.md](intentional-risks.md) — what was intentionally weak
