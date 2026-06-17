# Intentional risks

<!-- M11 T175: matrix compiled from live verification. Regenerate: make verify-vuln-matrix -->

**Verification matrix:** see [`artifacts/sample/vuln-matrix-latest.json`](../artifacts/sample/vuln-matrix-latest.json) and [`docs/ci-cd.md`](ci-cd.md).

This document is the **auditor-facing register**: every weakness below is deliberate, labeled in-cluster, and captured by verification scripts. Each entry includes location, rationale, labels, evidence path, and production remediation.

## Integration matrix (spec §7)

| # | ID | Task | Evidence |
|---|-----|------|----------|
| 1 | vuln-1 | T165 | `make verify-vuln-matrix` → `artifacts/sample/vuln-01-*.txt` |
| 2 | vuln-2 | T166 | `artifacts/sample/vuln-02-*.txt` |
| 3 | vuln-3 | T167 | `artifacts/sample/vuln-03-*.txt` |
| 4 | vuln-4 | T168 | `artifacts/sample/vuln-04-*.txt` |
| 5 | vuln-5 | T169 | `artifacts/sample/vuln-05-*.txt` |
| 6 | vuln-6 | T170 | `artifacts/sample/vuln-06-*.txt` |
| 7 | vuln-7 | T171 | `artifacts/sample/vuln-07-*.txt` |
| 8 | vuln-8 | T172 | `artifacts/sample/vuln-08-*.txt` |
| 9 | vuln-9 | T173 | `artifacts/sample/vuln-09-*.txt` |
| 10 | vuln-10 | T174–T183 | `artifacts/sample/vuln-10-*.txt` |

Regenerate matrix: `make verify-vuln-matrix` then `make compile-vuln-matrix`.

---

## Risk register (auditor-facing)

### vuln-1 — Internet-facing API exposure

| Field | Value |
|---|---|
| **Task** | T165 |
| **Location** | `k8s/base/ingress.yaml`; `backend/src/routes/debug.ts`; `backend/src/middleware/auth.ts` (route excluded from auth) |
| **What** | Public ALB ingress + unauthenticated `GET /api/debug/status` (harmless metadata only — never returns secrets) |
| **Labels** | Ingress and backend resources tagged `cnapp.demo/risk-id: vuln-1` where applicable |
| **ATT&CK** | T1190 — Exploit Public-Facing Application |
| **Why intentional** | Demonstrates internet → ALB → backend chain for CNAPP exposure findings |
| **Evidence** | `make verify-vuln-matrix` (vuln 1); `make eks-verify-alb`; `artifacts/sample/trivy-backend.json` (runtime correlation) |
| **Remediation** | Add WAF / AWS Shield; require auth on all non-health routes; use internal ingress for admin APIs; restrict ALB security group source ranges in non-demo environments |

### vuln-2 — Broad S3 IAM on backend role

| Field | Value |
|---|---|
| **Task** | T166 |
| **Location** | `infra/cdk/lib/iam-stack.ts` — inline policy `Vuln2BroadS3Access` |
| **What** | `s3:*` on `arn:aws:s3:::taskvault-*` and `arn:aws:s3:::taskvault-*/*` |
| **Labels** | `taskvault-backend-role` tagged `cnapp.demo/risk-id: vuln-2` |
| **ATT&CK** | T1078.004 — Valid Accounts: Cloud Accounts |
| **Why intentional** | Shows over-privileged workload IAM vs scoped worker role (contrast) |
| **Evidence** | `scripts/verify-vuln-02.sh`; `artifacts/sample/checkov.json` (`CKV_AWS_109`); IAM simulate in vuln-02 evidence |
| **Remediation** | Replace `s3:*` with least-privilege actions on specific bucket ARNs; use ABAC or prefix-scoped policies; separate read vs write roles |

### vuln-3 — backend-sa can list Secrets

| Field | Value |
|---|---|
| **Task** | T167 |
| **Location** | `k8s/base/rbac.yaml` — Role `backend-secret-reader`, RoleBinding to `backend-sa` |
| **What** | `backend-sa` may `get`, `list` Secrets in `demo-prod` |
| **Labels** | RBAC objects: `cnapp.demo/risk-id: vuln-3` |
| **ATT&CK** | T1098.006 — Additional Container Cluster Roles |
| **Why intentional** | K8s identity weakness correlated with IRSA cloud pivot (vuln-6) |
| **Evidence** | `kubectl auth can-i list secrets --as=system:serviceaccount:demo-prod:backend-sa`; `scripts/verify-vuln-03.sh` |
| **Remediation** | Remove Secret list permissions; use External Secrets Operator with scoped access; enforce RBAC audits and deny-by-default Roles |

### vuln-4 — Fake credentials in repo and image

| Field | Value |
|---|---|
| **Task** | T168 |
| **Location** | `.env.example`; `backend/test/fixtures/fake-secrets.txt`; `backend/Dockerfile` (COPY fixture layer) |
| **What** | Dead placeholders: `AKIAFAKEDEMO123456`, `sk_test_fake_demo_value` |
| **Labels** | Comments in fixtures; not used by application code |
| **ATT&CK** | T1552.001 — Credentials In Files |
| **Why intentional** | Exercises Gitleaks + Trivy secret scanners and GitHub→image correlation |
| **Evidence** | `scripts/verify-vuln-04.sh`; `artifacts/sample/gitleaks.json`; `artifacts/sample/trivy-backend.json` |
| **Remediation** | Never commit secrets; use secret managers; `.env.example` with empty placeholders; image scanning in CI with **blocking** gate; cosign signing |

### vuln-5 — Privileged worker + hostPath

| Field | Value |
|---|---|
| **Task** | T169 |
| **Location** | `k8s/base/worker-deployment.yaml` |
| **What** | `securityContext.privileged: true`; `hostPath` mount of `/` |
| **Labels** | `cnapp.demo/risk-id: vuln-5` on worker Deployment |
| **ATT&CK** | T1611 — Escape to Host |
| **Why intentional** | Pod-to-node escape preconditions for Kubescape / CNAPP runtime posture |
| **Evidence** | `scripts/verify-vuln-05.sh`; `artifacts/sample/kubescape.json` |
| **Remediation** | Drop privileged flag; remove hostPath; use Pod Security Standards (restricted); seccomp/AppArmor profiles |

### vuln-6 — IRSA bridge to Secrets Manager

| Field | Value |
|---|---|
| **Task** | T170 |
| **Location** | `k8s/base/serviceaccounts.yaml` (IRSA annotation); `k8s/overlays/eks/serviceaccount-irsa-patch.yaml`; `infra/cdk/lib/iam-stack.ts` |
| **What** | `backend-sa` → `taskvault-backend-role` with `secretsmanager:GetSecretValue` on `taskvault/demo/*` |
| **Labels** | SA + role tagged for demo risks |
| **ATT&CK** | T1552.005 — Cloud Instance Metadata / WebIdentity |
| **Why intentional** | Core of pod → cloud credential pivot in master attack path |
| **Evidence** | `scripts/verify-vuln-06.sh`; `make eks-verify-irsa-s3`; CloudTrail IRSA events |
| **Remediation** | Scope Secrets Manager paths; use dedicated secret per workload; rotate secrets; monitor `AssumeRoleWithWebIdentity` |

### vuln-7 — No default-deny NetworkPolicies

| Field | Value |
|---|---|
| **Task** | T171 |
| **Location** | `k8s/base/networkpolicies.yaml` — only `allow-*` policies; **no** `default-deny-ingress` / `default-deny-egress` |
| **What** | Broad east-west and outbound connectivity in `demo-prod` |
| **Labels** | NetworkPolicy objects document intentional omission |
| **ATT&CK** | T1046 — Network Service Discovery |
| **Why intentional** | Segmentation finding for CNAPP; local overlay adds egress to Postgres/LocalStack only |
| **Evidence** | `scripts/verify-vuln-07.sh`; `artifacts/sample/kubescape.json` |
| **Remediation** | Add default-deny ingress/egress; namespace-scoped allow lists; service mesh mTLS |

### vuln-8 — Vulnerable root backend image

| Field | Value |
|---|---|
| **Task** | T172 |
| **Location** | `backend/Dockerfile` (`node:16-alpine`, no USER); `backend/package.json` (`lodash@4.17.15`); `k8s/base/backend-deployment.yaml` (`runAsUser: 0`, no CPU/memory limits) |
| **What** | Outdated base + unused vulnerable dep + root container correlated with ALB exposure |
| **Labels** | Dockerfile label `cnapp.demo/risk-id`; deployment labels |
| **ATT&CK** | CVE/CWE class (software vulnerability) |
| **Why intentional** | Scanner + runtime correlation; medium alone, critical with vuln-1 |
| **Evidence** | `scripts/verify-vuln-08.sh`; `artifacts/sample/trivy-backend.json`, `grype-backend.json` |
| **Remediation** | Upgrade base image; pin and patch dependencies; run as non-root (`runAsNonRoot: true`); set resource limits; block deploy on scan failures |

### vuln-9 — S3 versioning disabled on sensitive bucket

| Field | Value |
|---|---|
| **Task** | T173 |
| **Location** | `infra/cdk/lib/storage-stack.ts` (`versioned: false`); `scripts/seed-demo-data.ts` (uploads to `uploads/sensitive/`) |
| **What** | `taskvault-user-files` without versioning; synthetic “crown jewel” CSV fixtures |
| **Labels** | CDK tags on bucket construct |
| **ATT&CK** | T1530 — Data from Cloud Storage |
| **Why intentional** | Data-store weakness reachable via vuln-2 IAM |
| **Evidence** | `scripts/verify-vuln-09.sh`; `aws s3api get-bucket-versioning`; `artifacts/sample/checkov.json` (`CKV_AWS_21`) |
| **Remediation** | Enable versioning + MFA delete; S3 Object Lock for sensitive prefixes; separate accounts for sensitive data |

### vuln-10 — CI/CD supply-chain weaknesses

| Field | Value |
|---|---|
| **Task** | T174–T183 |
| **Location** | `.github/workflows/deploy.yml`; `infra/cdk/lib/github-oidc-role-stack.ts`; contrast: `.github/workflows/build.yml` |
| **What** | `permissions: write-all`; unpinned `@main` action (`nick-fields/retry@main`); no `needs: security-scan`; no cosign; broad OIDC trust `repo:<org>/taskvault-demo:*` |
| **Labels** | Documented in workflow comments |
| **ATT&CK** | T1195.002 — Supply Chain Compromise |
| **Why intentional** | Shows weak pipeline vs `build.yml` baseline; cloud OIDC role over-permissioned |
| **Evidence** | `scripts/verify-vuln-10.sh`; `artifacts/sample/vuln-10-*.txt`; `artifacts/sample/github-inventory.json` |
| **Remediation** | Pin actions by commit SHA; scope `permissions` per job; require security-scan + cosign verify before deploy; narrow OIDC to `refs/heads/main` + GitHub Environment; separate build vs deploy IAM roles |

**Good contrast:** `build.yml` uses `permissions: id-token: write` + `contents: read` and pins first-party actions to version tags.

---

## Scanner evidence (survives teardown)

After `make export-evidence`, see `artifacts/sample/`:

| Artifact | Vulns |
|---|---|
| `trivy-backend.json`, `grype-backend.json` | 4, 8 |
| `checkov.json` | 2, 9, 10 |
| `gitleaks.json` | 4 |
| `kubescape.json` | 3, 5, 7, 8 |
| `expected-*.json` | All (graph oracle) |

See [graph-contract.md](graph-contract.md) and [test-plan.md](test-plan.md).
