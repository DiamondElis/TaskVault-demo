# Test plan

Acceptance tests for the TaskVault CNAPP demo target. Run after deploy and before handing off to CNAPP evaluation.

Related: [runbook.md](runbook.md), [intentional-risks.md](intentional-risks.md), [graph-contract.md](graph-contract.md).

---

## 1. Smoke tests

### Local (`make test-demo`)

Runs `scripts/smoke-local.sh`:

- `GET /api/healthz` → `{"status":"ok"}`
- `GET /api/readyz` → `"database":true`
- Worker / frontend health (optional if not running)
- `backend/ROUTES.md` and `backend/migrations/` present

### EKS (`make smoke-eks`)

End-to-end via ALB (T160):

1. Resolve ALB hostname from `taskvault-public-ingress`
2. Register/login as demo admin (`admin@taskvault.demo` / `password123`)
3. Create task, upload file, trigger process job
4. Request admin report
5. Evidence → `artifacts/sample/eks-e2e-*.txt`

### Full M10 chain (`make eks-deploy-seed-verify`)

Runs: db-migrator → seed → smoke-eks → IRSA/S3 verify → worker flow → audit coverage → report cronjob.

---

## 2. Kubernetes — EndpointSlice presence (T103)

The CNAPP K8s connector maps `Service → EndpointSlice → Pod IP`. After deploying manifests, verify each ClusterIP Service generates EndpointSlices once backing pods are ready:

```bash
kubectl -n demo-prod get endpointslices -l kubernetes.io/service-name
kubectl -n demo-prod get endpointslices -l kubernetes.io/service-name=frontend-service -o yaml
kubectl -n demo-prod get endpointslices -l kubernetes.io/service-name=backend-service -o yaml
kubectl -n demo-prod get endpointslices -l kubernetes.io/service-name=worker-internal-service -o yaml
kubectl -n demo-prod get endpointslices -l kubernetes.io/service-name=metrics-service -o yaml
```

**Pass criteria:** each of `frontend-service`, `backend-service`, `worker-internal-service`, and `metrics-service` has at least one EndpointSlice with ready addresses when workloads are running.

---

## 3. Per-vulnerability verification (M11)

Run all:

```bash
make verify-vuln-matrix
make compile-vuln-matrix
```

Or individually:

| Vuln | Command | Script |
|---|---|---|
| 1 | `RUN_VULN=1 make verify-vuln-matrix` | `scripts/verify-vuln-01.sh` — ALB + `/api/debug/status` |
| 2 | `RUN_VULN=2 make verify-vuln-matrix` | `scripts/verify-vuln-02.sh` — `s3:*` IAM policy |
| 3 | `RUN_VULN=3 make verify-vuln-matrix` | `scripts/verify-vuln-03.sh` — SA can list Secrets |
| 4 | `RUN_VULN=4 make verify-vuln-matrix` | `scripts/verify-vuln-04.sh` — Gitleaks + Trivy secret |
| 5 | `RUN_VULN=5 make verify-vuln-matrix` | `scripts/verify-vuln-05.sh` — privileged worker |
| 6 | `RUN_VULN=6 make verify-vuln-matrix` | `scripts/verify-vuln-06.sh` — IRSA + Secrets Manager |
| 7 | `RUN_VULN=7 make verify-vuln-matrix` | `scripts/verify-vuln-07.sh` — missing default-deny netpol |
| 8 | `RUN_VULN=8 make verify-vuln-matrix` | `scripts/verify-vuln-08.sh` — Trivy CVEs + root pod + ALB |
| 9 | `RUN_VULN=9 make verify-vuln-matrix` | `scripts/verify-vuln-09.sh` — S3 versioning off |
| 10 | `RUN_VULN=10 make verify-vuln-matrix` | `scripts/verify-vuln-10.sh` — deploy.yml + OIDC role |

Evidence lands in `artifacts/sample/vuln-{NN}-*.txt` and updates `vuln-matrix-latest.json`.

---

## 4. Local kind validation (M7)

```bash
make k8s-local-validate    # workloads + vuln-3/5/7 signals
make k8s-kubescape         # NSA framework scan
make k8s-lint              # kubeconform on manifests
```

---

## 5. Scanner and graph oracle (M13)

```bash
make export-evidence
```

**Pass criteria:**

- All 13 files in `artifacts/sample/` non-empty (see [graph-contract.md](graph-contract.md))
- Trivy reports HIGH/CRITICAL CVEs + fake secret in backend image
- Gitleaks flags vuln-4 fixtures in `.env.example` / `fake-secrets.txt`
- Checkov reports `CKV_AWS_21`, `CKV_AWS_109`, OIDC/GitHub signals
- Kubescape reports privileged, hostPath, limits, networkPolicy signals
- `expected-attack-paths.json` contains `master-code-to-cloud`

---

## 6. CI/CD pipeline (M12)

```bash
make ci-verify-pipeline
```

Validates GitHub Actions workflows ran, security-scan artifacts exist, deploy.yml retains intentional weaknesses (no scan gate, no cosign).

---

## 7. Manual spot checks

```bash
# vuln-3 — RBAC
kubectl auth can-i list secrets --as=system:serviceaccount:demo-prod:backend-sa -n demo-prod
# expect: yes

# vuln-9 — S3 versioning
aws s3api get-bucket-versioning --bucket taskvault-user-files
# expect: Status absent or Suspended

# vuln-1 — public debug route
curl -s "http://$(kubectl -n demo-prod get ingress taskvault-public-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')/api/debug/status"

# IRSA annotation
kubectl -n demo-prod get sa backend-sa -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}'
```

---

## 8. Acceptance summary

| Gate | Command | Required for CNAPP handoff |
|---|---|---|
| EKS workloads healthy | `make eks-verify` | Yes |
| Demo data seeded | `make eks-seed-demo` | Yes |
| E2E smoke | `make smoke-eks` | Yes |
| All 10 vulns evidenced | `make verify-vuln-matrix` | Yes |
| Graph oracle | `make export-evidence` | Yes |
| EndpointSlices | §2 above | Yes (K8s connector) |

**Final acceptance:** A fresh engineer can deploy from the README; app runs on EKS; ALB exposes frontend/backend; backend reaches S3 via IRSA; master attack path is live; scanner + expected-graph artifacts exist; cleanup destroys everything; no real secrets anywhere.
