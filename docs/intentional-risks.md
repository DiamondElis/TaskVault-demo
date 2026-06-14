# Intentional risks

<!-- M11 T175: matrix compiled from live verification. Regenerate: make verify-vuln-matrix -->

**Verification matrix:** see [`artifacts/sample/vuln-matrix-latest.json`](../artifacts/sample/vuln-matrix-latest.json) and [`docs/ci-cd.md`](ci-cd.md).

## Integration matrix (spec §7)

| # | ID | Task | Evidence |
|---|-----|------|----------|
| 1 | vuln-1 | T165 | `(run make verify-vuln-matrix)` |
| 2 | vuln-2 | T166 | `(run make verify-vuln-matrix)` |
| 3 | vuln-3 | T167 | `(run make verify-vuln-matrix)` |
| 4 | vuln-4 | T168 | `(run make verify-vuln-matrix)` |
| 5 | vuln-5 | T169 | `(run make verify-vuln-matrix)` |
| 6 | vuln-6 | T170 | `(run make verify-vuln-matrix)` |
| 7 | vuln-7 | T171 | `(run make verify-vuln-matrix)` |
| 8 | vuln-8 | T172 | `(run make verify-vuln-matrix)` |
| 9 | vuln-9 | T173 | `(run make verify-vuln-matrix)` |
| 10 | vuln-10 | T174–T183 | `.github/workflows/deploy.yml`, `artifacts/sample/vuln-10-*.txt` |

## vuln-10 — CI/CD supply-chain (intentional)

**Cloud (T140):** `infra/cdk/lib/github-oidc-role-stack.ts` creates `taskvault-github-deploy-role` with:

- Broad OIDC trust: `repo:<org>/taskvault-demo:*` (any branch/ref — **T179**)
- Over-privileged policies: ECR power-user, EKS API, broad S3 write

**GitHub Actions (T178–T183):**

| Weakness | Where | Intentional? |
|----------|-------|--------------|
| `permissions: write-all` | `.github/workflows/deploy.yml` | **Yes** — over-broad workflow token |
| Unpinned third-party `@main` action | `deploy.yml` → `nick-fields/retry@main` | **Yes** — supply-chain pin risk |
| **No scan-gate** before deploy | `deploy.yml` has no `needs: security-scan` | **Yes** (T177/T183) |
| **No cosign / image signing** | absent from `deploy.yml` | **Yes** (T183) |
| Broad OIDC role assumption | `build.yml` + `deploy.yml` → same `AWS_OIDC_ROLE_ARN` | **Yes** — any branch can assume role |

**Good contrast (T176):** `.github/workflows/build.yml` uses tightly-scoped `permissions: id-token: write` + `contents: read` and pins first-party actions to version tags (`@v4`).

**Remediation (production):** pin all actions by commit SHA; scope `permissions` per job; require `security-scan` + cosign verification before deploy; narrow OIDC trust to `refs/heads/main` + GitHub Environment; use a least-privilege build role separate from deploy.

## vuln-8 — Backend runs as root without resource limits

The `backend-api` Deployment (`k8s/base/backend-deployment.yaml`) intentionally sets `securityContext.runAsUser: 0` and **omits CPU/memory limits** on the container. This reinforces the outdated `node:16-alpine` backend image (also vuln-8) and should read as a deliberate medium-severity posture finding, not an oversight.

## vuln-7 — No default-deny NetworkPolicies

`k8s/base/networkpolicies.yaml` defines four `allow-*` policies only. **`default-deny-ingress` and `default-deny-egress` are deliberately absent**, leaving broad east-west and outbound connectivity in `demo-prod`. The omission is intentional for CNAPP segmentation findings.

The `overlays/local` netpol patch adds egress to ports 4566/5432 so worker/backend can reach docker-compose LocalStack and Postgres on the kind Docker network; it does **not** add default-deny policies.

## vuln-9 — S3 versioning disabled (CDK)

`infra/cdk/lib/storage-stack.ts` sets `versioned: false` on `taskvault-user-files`. Checkov rule `CKV_AWS_21` should flag this.

## vuln-2 / vuln-6 — Backend IAM role (CDK)

`infra/cdk/lib/iam-stack.ts` grants `s3:*` on `arn:aws:s3:::taskvault-*` (vuln-2) and `secretsmanager:GetSecretValue` on `taskvault/demo/*` (vuln-6).
