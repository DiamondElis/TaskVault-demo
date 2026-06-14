# Local Kubernetes (kind) validation

TaskVault manifests can be exercised on a local [kind](https://kind.sigs.k8s.io/) cluster before EKS deploy. This path validates RBAC, NetworkPolicy omissions, privileged workloads, and scanner findings without AWS cost.

## Quick start

```bash
make kind-up          # kind cluster + ingress-nginx + Postgres/LocalStack
make docker-build     # if images not built yet
make kind-load-images # load taskvault-*:local into kind
make k8s-local-up     # apply overlays/local + db-migrator
make k8s-local-validate  # T114–T117 checks + evidence
make k8s-kubescape    # T118 scanner output
```

Tear down:

```bash
make kind-down
make local-down       # optional: stop Postgres/LocalStack volumes
```

## Local vs EKS differences

| Concern | kind (local) | EKS (demo-prod) |
|--------|----------------|-----------------|
| Ingress | **ingress-nginx** on `localhost:8088` | **AWS ALB** via `taskvault-public-ingress` |
| IRSA | Dummy `eks.amazonaws.com/role-arn` placeholders | Real OIDC → `taskvault-backend-role` / `taskvault-worker-role` |
| S3 / SQS | Static kind-network IP → docker-compose LocalStack (`kind-connect-infra.sh`) | Regional AWS endpoints + IAM credentials |
| Postgres | Static kind-network IP → docker-compose Postgres (`kind-connect-infra.sh`) | RDS `taskvault-db` |
| NetworkPolicy | `netpol-localstack-patch.yaml` adds egress 4566/5432 for LocalStack/Postgres | EKS uses 443-only SQS/RDS ports |
| Secrets Manager | Disabled (`USE_SECRETS_MANAGER=false`) | Enabled via IRSA |
| CloudTrail / Inspector | Not present | Enabled in demo account |

Intentional vulnerability **labels and manifest shape** match EKS; only the cloud integration layer differs.

## Ingress access

After `make k8s-local-up`:

- Frontend: http://localhost:8088/
- Backend health: http://localhost:8088/api/healthz (via ingress path to backend — or port-forward `backend-service:8080`)

The ALB-specific annotations in `k8s/base/ingress.yaml` are replaced in `overlays/local` with `kubernetes.io/ingress.class: nginx`.

## Evidence artifacts

Validation and scans write to `artifacts/sample/`:

- `k8s-local-validation-*.txt` — workload + vuln-3/5/7 verification
- `k8s-worker-pod-*.yaml` — privileged worker evidence
- `kubescape-kind-*.json` — kubescape scan output
