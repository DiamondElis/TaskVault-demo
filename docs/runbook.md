# Runbook

Operational steps to deploy, seed, validate, and export evidence for the TaskVault demo. For architecture context see [architecture.md](architecture.md); for EKS details see [eks-deploy.md](eks-deploy.md).

**AWS profile:** `taskvault-deploy` in `us-east-1` (see [aws-deploy-profile.md](aws-deploy-profile.md)).

---

## 1. Prerequisites

- Docker Desktop (or Docker Engine) running
- AWS CLI v2, `kubectl`, Node.js 20+
- CDK bootstrap once: `cd infra/cdk && npx cdk bootstrap`
- Set `githubOrg` in `infra/cdk/cdk.json` before deploying GitHub OIDC stack

---

## 2. Local development

```bash
cp .env.example .env
make local-up          # Postgres + LocalStack + app containers
make seed-demo         # idempotent DB + S3 fixtures
make test-demo         # smoke-local.sh health checks
```

Stop: `make local-down`

---

## 3. Local Kubernetes (kind)

```bash
make kind-up
make k8s-local-up
make k8s-local-validate
make k8s-kubescape      # optional posture scan
```

Tear down: `make kind-down`

See [kind-local.md](kind-local.md).

---

## 4. AWS / EKS deploy

### Phase A — Infrastructure

```bash
make cdk-deploy-foundation   # Network, KMS, ECR, Storage, RDS, Observability
make cdk-deploy-eks          # EKS cluster + ALB controller (Helm)
make eks-verify              # nodes, add-ons, OIDC
```

Or all CDK stacks: `make cdk-deploy`

### Phase B — IAM and images

```bash
make cdk-deploy-iam          # IRSA roles + GitHub OIDC
make ecr-push-bootstrap      # push :bootstrap images (linux/amd64)
```

### Phase C — Workloads

```bash
make k8s-deploy              # applies overlays/eks with CFN output substitution
make eks-verify-alb          # vuln-1 ALB + /api/debug/status
make eks-verify-logs         # CloudWatch /taskvault/* log flow
```

### Phase D — Data and validation

```bash
make eks-deploy-seed-verify  # migrator → seed → smoke → audit → cronjob evidence
# Or step-by-step:
make eks-run-db-migrator
make eks-seed-demo
make smoke-eks
```

---

## 5. Vulnerability verification (M11)

Requires live EKS + seeded data:

```bash
make verify-vuln-matrix      # T165–T174 per-vuln evidence
make compile-vuln-matrix     # refresh vuln-matrix-latest.json + docs stub
```

Single vuln: `RUN_VULN=3 make verify-vuln-matrix`

---

## 6. Evidence export (M13)

Survives environment teardown — regenerates inventories, scanner outputs, validates oracle:

```bash
make export-evidence
```

Outputs in `artifacts/sample/`. See [graph-contract.md](graph-contract.md).

---

## 7. CI/CD verification (M12)

```bash
make ci-verify-pipeline      # T184 — workflow + scan artifact checks
```

Requires GitHub repo variables (`AWS_OIDC_ROLE_ARN`) and successful workflow runs.

---

## 8. Validate demo health

| Target | Command |
|---|---|
| Local smoke | `make test-demo` |
| EKS end-to-end | `make smoke-eks` |
| Full M10 chain | `make eks-deploy-seed-verify` |
| All vulns | `make verify-vuln-matrix` |
| Graph oracle | `make export-evidence` |

---

## 9. Troubleshooting

| Symptom | Action |
|---|---|
| EKS nodes not Ready | `make eks-verify`; check node group in console |
| ALB not provisioned | Re-run `scripts/eks-install-alb-controller.sh`; check IAM for ALB controller role |
| Backend CrashLoop / RDS SSL | Verify `db-credentials` secret; check worker/backend SSL env (see eks-deploy.md) |
| CloudWatch logs empty | Re-run `scripts/eks-install-cloudwatch-observability.sh` |
| `k8s-deploy` IRSA wrong | Always use `make k8s-deploy` (not raw `kubectl apply -k`) |
| RDS UPDATE_ROLLBACK | Do not add `databaseName` to existing RDS — see eks-deploy.md |
| Docker not running | Required for `export-evidence` image scans |

---

## 10. Destroy

See [cleanup.md](cleanup.md):

```bash
make destroy
```

---

## Quick reference — Make targets

```
local-up / local-down / docker-build / seed-demo / test-demo
kind-up / kind-down / k8s-local-up / k8s-local-validate / k8s-kubescape
cdk-synth / cdk-deploy / cdk-deploy-foundation / cdk-deploy-eks / cdk-deploy-iam
ecr-push-bootstrap / k8s-deploy
eks-verify / eks-verify-alb / eks-verify-logs / eks-deploy-seed-verify / smoke-eks
verify-vuln-matrix / compile-vuln-matrix / export-evidence / ci-verify-pipeline
destroy
```
