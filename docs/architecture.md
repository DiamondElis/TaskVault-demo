# Architecture

TaskVault is a deliberately vulnerable three-service demo (`frontend`, `backend-api`, `worker`) deployed on AWS EKS. It exists to produce a believable **code → image → runtime → cloud identity → data** graph for CNAPP evaluation.

Full build specification: [taskvault-architecture.md](taskvault-architecture.md) (links to [README § Architecture](../README.md#architecture--build-specification)).

---

## Resolved naming table

Canonical names — use these everywhere (manifests, CDK, console, docs):

| Layer | Canonical name |
|---|---|
| AWS account | `taskvault-demo-prod` (dedicated, isolated) |
| Region | `us-east-1` |
| VPC | `taskvault-vpc` — `10.0.0.0/16` |
| Public subnets | `taskvault-public-a` (`10.0.0.0/20`), `taskvault-public-b` (`10.0.16.0/20`) |
| Private subnets | `taskvault-private-a` (`10.0.128.0/20`), `taskvault-private-b` (`10.0.144.0/20`) |
| EKS cluster | `taskvault-eks` |
| Namespace | `demo-prod` |
| ECR repos | `taskvault-frontend`, `taskvault-backend`, `taskvault-worker` |
| S3 (user files) | `taskvault-user-files` |
| S3 (reports) | `taskvault-reports` |
| RDS | `taskvault-db` (Postgres) |
| SQS | `taskvault-jobs` |
| Secrets Manager | `taskvault/demo/db`, `taskvault/demo/app` |
| KMS alias | `alias/taskvault-demo` |
| Backend IAM role | `taskvault-backend-role` |
| Worker IAM role | `taskvault-worker-role` |
| GitHub deploy role | `taskvault-github-deploy-role` |
| Public ingress | `taskvault-public-ingress` |
| ServiceAccounts | `frontend-sa`, `backend-sa`, `worker-sa`, `db-migrator-sa`, `report-job-sa` |
| Deployments | `frontend`, `backend-api`, `worker` |

Every intentional risk is labeled in-cluster: `cnapp.demo/intentional-risk: "true"` and `cnapp.demo/risk-id: vuln-N`.

---

## System topology

```
                              Internet
                                 │
                                 ▼
              ┌──────────────────────────────────────┐
              │  Internet-facing ALB (no WAF)      │  AWS — vuln-1
              └──────────────────┬───────────────────┘
                                 │
              ┌──────────────────▼───────────────────┐
              │  taskvault-public-ingress            │  K8s — vuln-1
              └──────────┬─────────────┬─────────────┘
                         │             │
            frontend-service      backend-service
                         │             │
                         ▼             ▼
                   frontend Pod   backend-api Pod ── node:16 + root + CVEs   vuln-8
                                       │ uses backend-sa (list secrets)      vuln-3
                                       │
                         IRSA ────────▼
              ┌──────────────────────────────────────┐
              │  taskvault-backend-role              │  AWS — vuln-2, vuln-6
              │  s3:* on taskvault-*                 │
              │  secretsmanager:GetSecretValue       │
              └──────────┬─────────────┬─────────────┘
                         │             │
                         ▼             ▼
              taskvault-user-files   Secrets Manager / RDS
              (versioning OFF)       taskvault/demo/*
              uploads/sensitive/*    vuln-9

   Worker plane:  SQS taskvault-jobs → worker Pod (privileged + hostPath /)   vuln-5
   Network:       demo-prod — allow-only NetworkPolicies, no default-deny     vuln-7

   Code plane:    GitHub → build → ECR → EKS
                  .env.example fake keys (vuln-4)
                  deploy.yml write-all + @main (vuln-10)
```

### CDK stacks (`infra/cdk/lib/`)

| Stack | Creates |
|---|---|
| `TaskvaultNetwork` | VPC, subnets, IGW, NAT, security groups |
| `TaskvaultKms` | `alias/taskvault-demo` |
| `TaskvaultEcr` | Three ECR repositories, scan-on-push |
| `TaskvaultStorage` | S3 buckets, SQS queue, app secret |
| `TaskvaultRds` | Postgres in private subnets |
| `TaskvaultEks` | Cluster, node group, OIDC, ALB controller IRSA |
| `TaskvaultIam` | `taskvault-backend-role`, `taskvault-worker-role` (IRSA) |
| `TaskvaultGithubOidc` | GitHub OIDC provider + deploy role |
| `TaskvaultObservability` | CloudWatch log groups, CloudTrail, Inspector |

### Kubernetes (`k8s/base/` + `overlays/eks|local`)

Workloads run in `demo-prod`. EKS overlay substitutes ECR image URIs and IRSA role ARNs from CloudFormation outputs at deploy time (`make k8s-deploy`).

---

## Master attack path (spec §8)

The demo's primary teaching chain — each hop has evidence from a different connector:

```
Internet
 → Public ALB (internet-facing, no WAF)                         [AWS]      vuln-1
 → taskvault-public-ingress                                     [K8s]      vuln-1
 → backend-service → EndpointSlice → backend-api Pod            [K8s]
 → vulnerable + root backend container image                    [scanner]  vuln-8
 → backend-sa                                                    [K8s]      vuln-3
 → IRSA → taskvault-backend-role                                 [AWS]      vuln-6
 → s3:* on taskvault-* + secretsmanager:GetSecretValue          [AWS]      vuln-2 / vuln-6
 → taskvault-user-files (versioning off) / uploads/sensitive/*  [AWS]      vuln-9
```

**Critical toxic combination** (what a CNAPP should rank highest):

```
internet exposure (1)
+ vulnerable running container (8)
+ weak K8s identity/RBAC (3)
+ AWS workload credential path (6)
+ broad IAM data access (2)
+ sensitive S3 prefix with weak protection (9)
+ weak network egress controls (7)
= one Critical, fully-evidenced code-to-cloud attack path
```

Secondary paths: GitHub leaked-key correlation (4); CI/CD OIDC takeover (10); privileged worker pivot (5 + 7).

Acceptance oracle: `artifacts/sample/expected-attack-paths.json` — see [graph-contract.md](graph-contract.md).

---

## Data flow

1. User hits ALB → frontend or `/api/*` on backend.
2. Backend authenticates (JWT), reads/writes RDS, stores files in `taskvault-user-files`, enqueues SQS jobs.
3. Worker consumes jobs, reads S3, writes results, emits audit JSON to CloudWatch (`/taskvault/{backend,worker,frontend}`).
4. IRSA injects AWS credentials into backend/worker pods via `backend-sa` / `worker-sa` annotations.

Sensitive fixture prefixes (synthetic CSVs only):

```
taskvault-user-files/uploads/sensitive/
  payroll-export-demo.csv
  customer-records-demo.csv
  internal-access-review-demo.csv
```

---

## Related docs

| Doc | Purpose |
|---|---|
| [taskvault-architecture.md](taskvault-architecture.md) | Link to full README build spec |
| [threat-model.md](threat-model.md) | ATT&CK mapping, trust boundaries |
| [graph-contract.md](graph-contract.md) | CNAPP node/edge/findings schema |
| [intentional-risks.md](intentional-risks.md) | Auditor-facing risk register |
| [eks-deploy.md](eks-deploy.md) | EKS phased deploy |
| [runbook.md](runbook.md) | Deploy / operate / validate |
| [cleanup.md](cleanup.md) | Teardown order |
