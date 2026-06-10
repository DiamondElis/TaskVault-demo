# TaskVault — CNAPP demo target environment (intentionally vulnerable, demo-only)

Deliberately vulnerable cloud-native demo app (AWS + EKS + GitHub) for CNAPP evaluation. Three services — `frontend`, `backend-api`, `worker` — produce a code → image → runtime → cloud-identity → data graph with intentional posture weaknesses.

## Safety guardrails

> **Safety guardrails (non-negotiable, baked into every section below):**
> - Fake credentials only. Every "secret" is a syntactically-valid-but-dead placeholder.
> - One **dedicated, isolated AWS account** (`taskvault-demo-prod`), single region (`us-east-1`), no shared VPC peering, no production data.
> - No real PII — only `*-demo.csv` fixtures with synthetic rows.
> - No exploit payloads. The vulnerabilities are *configuration weaknesses and posture findings*, not weaponized code.
> - Every intentional risk is labeled in-cluster (`cnapp.demo/intentional-risk: "true"`) and documented in `docs/intentional-risks.md`.
> - A `make destroy` path that fully tears the environment down.

## Repo layout

```
taskvault-demo/
  frontend/           UI (stub until app milestone)
  backend/            API, migrations/, src/db/
  worker/             SQS consumer (stub)
  infra/cdk/          AWS CDK (stub)
  k8s/                EKS manifests (stub)
  scripts/            seed-demo-data.ts, export-evidence.sh, validate-demo.sh
  docs/               architecture, threat-model, runbook, … (stubs until M14)
  artifacts/sample/   scanner outputs + expected-*.json (M13)
```

## Local run

1. `cp .env.example .env`
2. `make local-up` — Postgres 16 + LocalStack (S3, SQS, Secrets Manager)
3. `make seed-demo` — idempotent DB migrations via `backend/src/db/migrate-and-seed.ts`
4. `cd backend && npm install && npm run dev` — API on `:8080` (`/api/healthz`, `/api/auth/*`, `/api/tasks`, `/api/files`, …)

Schema tables: `users`, `tasks`, `files`, `jobs`, `reports`, `audit_events`. Route map: `backend/ROUTES.md`. Manual migrations: `cd backend && npm run migrate:up` / `migrate:down`.

## Deploy to AWS

<!-- TODO: Account setup, make cdk-deploy, make k8s-deploy, validation steps. -->

## Cleanup

<!-- TODO: make destroy, account teardown checklist. See docs/cleanup.md. -->

## Intentional risks

Ten deliberate vulnerabilities (VULN 1–10) — see [spec §7](#7-the-10-intentional-vulnerabilities--integration-matrix) and `docs/intentional-risks.md` (filled M14).

## Links

- [Architecture & build specification](#architecture--build-specification) (below)
- `docs/architecture.md`, `docs/graph-contract.md`, `docs/runbook.md` (stubs until M14)

---

## Architecture & Build Specification

> **What this is:** a deliberately, *controllably* vulnerable cloud-native app (AWS + EKS + GitHub) whose only job is to produce a believable code → image → runtime → cloud-identity → data reality that your CNAPP can ingest, graph, and explain.
> **What this is not:** the CNAPP, a real SaaS product, or anything that ships real secrets or working exploit code.

---

## 1. Naming decision (read this first)

The two source documents drift between two naming schemes — **TaskVault** (`frontend`/`backend-api`/`worker`, namespace `demo-prod`, `taskvault-*` buckets) and an "Acme Payments" variant (`payments-api`/`invoice-worker`). The intentional-vulnerabilities doc is written entirely in **TaskVault** terms (`taskvault-backend-role`, `backend-sa`, `taskvault-user-files`, `taskvault-public-ingress`). 

**Canonical decision: standardize on TaskVault everywhere.** The Acme Payments wording is treated as illustrative only. The table below is the single source of truth for names; every manifest, CDK construct, and console step uses these.

| Layer | Canonical name |
|---|---|
| AWS account | `taskvault-demo-prod` (dedicated) |
| Region | `us-east-1` |
| VPC | `taskvault-vpc` — `10.0.0.0/16` |
| Public subnets | `taskvault-public-a` (`10.0.0.0/20`), `taskvault-public-b` (`10.0.16.0/20`) |
| Private subnets | `taskvault-private-a` (`10.0.128.0/20`), `taskvault-private-b` (`10.0.144.0/20`) |
| EKS cluster | `taskvault-eks` |
| Namespace | `demo-prod` |
| ECR repos | `taskvault-frontend`, `taskvault-backend`, `taskvault-worker` |
| S3 (crown jewel) | `taskvault-user-files` |
| S3 (reports) | `taskvault-reports` |
| S3 (optional public test) | `taskvault-public-test` (isolated, harmless static files only) |
| RDS (Postgres) | `taskvault-db` |
| SQS | `taskvault-jobs` |
| Secrets Manager | `taskvault/demo/db`, `taskvault/demo/app` |
| KMS key alias | `alias/taskvault-demo` |
| Backend IAM role | `taskvault-backend-role` |
| Worker IAM role | `taskvault-worker-role` |
| GitHub deploy role | `taskvault-github-deploy-role` |
| Public ingress | `taskvault-public-ingress` |

---

## 2. System overview

TaskVault is a 3-service (plus optional 4th) task-and-file app. Users register, log in, create tasks, upload files; the backend stores metadata in RDS and objects in S3, enqueues a job in SQS; a worker consumes the job, reads the object from S3, writes a fake analysis result back to RDS/S3, and emits structured logs. An admin route runs reports.

```
                              Internet
                                 │
                                 ▼
                       Public ALB (internet-facing, no WAF)        ← VULN 1 surface
                                 │
                       taskvault-public-ingress (ALB controller)
                 ┌───────────────┼───────────────────────────┐
                 ▼               ▼                           ▼
          frontend-service   backend-service          /api/debug/status  ← VULN 1 (unauth route)
                 │               │
                 ▼               ▼
           frontend Pod     backend-api Pod ── runs as root + vuln dep   ← VULN 8
                                 │   uses backend-sa
                                 ├── backend-sa can list K8s Secrets       ← VULN 3
                                 │
                                 │ IRSA: backend-sa → taskvault-backend-role  ← VULN 6 bridge
                                 ▼
                      taskvault-backend-role  (s3:* on taskvault-*,         ← VULN 2
                                               secretsmanager:GetSecretValue)
                       ┌─────────────┼──────────────────────┐
                       ▼             ▼                       ▼
              S3 taskvault-user-files   Secrets Manager     RDS taskvault-db
              versioning OFF,           taskvault/demo/db
              uploads/sensitive/*       ← VULN 6 target
              ← VULN 9

   Worker plane:  backend → SQS taskvault-jobs → worker Pod (privileged + hostPath:/)  ← VULN 5
                                                  uses worker-sa → taskvault-worker-role

   Namespace demo-prod: NO default-deny NetworkPolicy, broad egress                    ← VULN 7
   Code plane: GitHub repo → .env.example fake secret (VULN 4)
               → .github/workflows/deploy.yml: write-all + unpinned action (VULN 10)
               → builds images → ECR → EKS
```

### Services
| Service | Stack | K8s kind | Identity | Talks to |
|---|---|---|---|---|
| `frontend` | React/Vite (or Next.js) + nginx | Deployment | `frontend-sa` (no AWS) | backend-service |
| `backend-api` | Node.js (Express/Nest) + AWS SDK | Deployment | `backend-sa` → `taskvault-backend-role` (IRSA) | RDS, S3, SQS, Secrets Manager |
| `worker` | Node.js + AWS SDK | Deployment | `worker-sa` → `taskvault-worker-role` (IRSA) | SQS, S3, RDS |
| `admin-api` *(optional)* | reuse backend image | Deployment or in-backend route | `admin-sa` | same as backend |
| `db-migrator` | backend image, one-shot | Job | `db-migrator-sa` | RDS |
| `report-cronjob` | worker image, scheduled | CronJob | `report-job-sa` → S3 write | S3, RDS |

### App endpoints (wired to K8s probes where noted)
- Health: `GET /api/healthz` (liveness), `GET /api/readyz` (readiness), `GET /api/version`
- Auth: `POST /api/auth/register`, `POST /api/auth/login`, `POST /api/auth/logout`, `GET /api/me`
- Tasks: `POST|GET /api/tasks`, `GET|PATCH|DELETE /api/tasks/:id`
- Files: `POST /api/files/upload`, `GET /api/files`, `GET /api/files/:id`, `GET /api/files/:id/download-url`, `POST /api/files/:id/process`
- Admin: `POST /api/admin/reports/run`, `GET /api/admin/reports`, `GET /api/admin/audit-events`, `GET /api/admin/users`, `GET /api/admin/files`
- **Intentional weak route:** `GET /api/debug/status` *(and/or `GET /api/admin/reports/preview`)* — no auth middleware, returns harmless metadata only (service name, build SHA, region, bucket name). **Never returns secrets.**
- Worker: `GET /worker/healthz`, `GET /worker/readyz`, `POST /internal/jobs/process`, `GET /internal/jobs/:id`
- Metrics: `GET /metrics` on every service

### Structured audit log contract (CloudWatch)
Every meaningful action emits one JSON line. Required `event_type` values: `login_success`, `login_failure`, `task_created`, `file_uploaded`, `s3_object_written`, `worker_job_created`, `worker_job_started`, `worker_job_completed`, `admin_report_requested`, `admin_report_written`. Shape:
```json
{"service":"backend-api","event_type":"file_uploaded","user_id":"user-123",
 "s3_bucket":"taskvault-user-files","s3_key":"uploads/sensitive/payroll-export-demo.csv",
 "request_id":"req-abc","timestamp":"2026-06-09T00:00:00Z"}
```

### S3 object layout (so the CNAPP can model prefixes / sensitive data stores)
```
taskvault-user-files/
  uploads/public/        ← harmless
  uploads/private/       ← per-user
  uploads/sensitive/     ← fake "crown jewel": payroll-export-demo.csv,
                            customer-records-demo.csv, internal-access-review-demo.csv
taskvault-reports/
  reports/admin/
```

---

## 3. AWS environment — per-service console build instructions

> Order matters: networking → identity foundations → registries/data → cluster → cluster add-ons → workload IAM → observability. Do all of this in `us-east-1` in the dedicated `taskvault-demo-prod` account.
>
> **Note on IaC:** the source spec mandates **AWS CDK (TypeScript)** as the real deliverable so the code connector can parse `infra/cdk/lib/*`. The console steps below are the *equivalent manual walkthrough* — useful for understanding and for a one-off demo, but the CDK stacks in §6 are the artifact of record. Build with CDK; use these steps to verify/inspect in the console.

### 3.1 VPC & networking → **VPC console**
1. **VPC → Create VPC → "VPC and more."** Name `taskvault`, CIDR `10.0.0.0/16`. 2 AZs, 2 public + 2 private subnets, 1 NAT gateway (one AZ is fine for a demo), enable DNS hostnames + resolution.
2. Confirm the wizard created: Internet Gateway (attached), public route tables routing `0.0.0.0/0` → IGW, private route tables routing `0.0.0.0/0` → NAT.
3. **Tag subnets for EKS/ALB discovery** (critical — the ALB controller relies on these):
   - Public subnets: `kubernetes.io/role/elb = 1`, `kubernetes.io/cluster/taskvault-eks = shared`
   - Private subnets: `kubernetes.io/role/internal-elb = 1`, `kubernetes.io/cluster/taskvault-eks = shared`
4. **Security groups** (EC2 console → Security Groups), all in `taskvault-vpc`:
   - `taskvault-alb-sg`: inbound 80/443 from `0.0.0.0/0`; outbound all. *(Internet-facing on purpose — feeds VULN 1.)*
   - `taskvault-node-sg`: created by EKS; you'll later allow ALB→node traffic.
   - `taskvault-rds-sg`: inbound 5432 **from `taskvault-node-sg` only** (keep RDS private — RDS is *not* the intentional exposure; the app-layer path is).

### 3.2 ECR → **ECR console**
1. **ECR → Repositories → Create** three private repos: `taskvault-frontend`, `taskvault-backend`, `taskvault-worker`.
2. On each, **enable scan on push** (Enhanced scanning via Inspector is best — see §3.11). This is what surfaces the **VULN 8** CVE.
3. Note the registry URI `…dkr.ecr.us-east-1.amazonaws.com`; CI pushes here.

### 3.3 KMS → **KMS console**
1. **KMS → Create key → Symmetric.** Alias `alias/taskvault-demo`. Key admins = your role; key users = (added later) the backend/worker roles and RDS/S3 service principals.
2. Used to encrypt S3, RDS, and Secrets Manager so the graph shows `KMSKey → {S3, RDS, Secret}` edges.

### 3.4 S3 → **S3 console**
1. **Create bucket `taskvault-user-files`** (us-east-1).
   - **Block Public Access: ON** (it stays private; exposure is via the workload role, not public ACL).
   - **Versioning: leave DISABLED.** ← **VULN 9** posture finding.
   - Default encryption: SSE-KMS with `alias/taskvault-demo`.
   - After creation, the seed job writes fake objects under `uploads/sensitive/` (see §7 fixtures).
2. **Create bucket `taskvault-reports`** — same settings; versioning may be on (contrast bucket).
3. *(Optional)* **`taskvault-public-test`** — only if you need to demo public-bucket detection. Keep it **empty or harmless static files**, isolated, clearly labeled. If you create it, that is the *only* place Block Public Access is relaxed, and nothing sensitive ever goes in it.

### 3.5 RDS (PostgreSQL) → **RDS console**
1. **RDS → Create database → PostgreSQL**, dev/test template, single-AZ db.t3.micro is fine.
2. DB identifier `taskvault-db`, set master creds (these go into Secrets Manager, **not** the repo).
3. **Connectivity:** place in `taskvault-vpc` **private** subnets, **Public access: No**, attach `taskvault-rds-sg`.
4. Storage encryption: ON, key `alias/taskvault-demo`.
5. **Store credentials in Secrets Manager** (next step) — RDS can auto-create the secret, or create it manually.

### 3.6 Secrets Manager → **Secrets Manager console**
1. **Store a new secret → Credentials for RDS** → `taskvault/demo/db` (username/password/host/port/dbname). Encrypt with `alias/taskvault-demo`.
2. Create `taskvault/demo/app` for the JWT signing secret (a random demo value).
3. **CNAPP note:** the connector collects *metadata/ARN/usage edges only* — never the secret value. The backend reads `taskvault/demo/db` at runtime via its IRSA role — this read permission is part of **VULN 6**.

### 3.7 SQS → **SQS console**
1. **Create queue → Standard**, name `taskvault-jobs`. Encryption SSE-KMS with `alias/taskvault-demo`.
2. Backend gets `sqs:SendMessage`; worker gets `sqs:ReceiveMessage`/`DeleteMessage` (scoped to this queue ARN — these are the *least-privilege* parts that contrast against the over-broad S3 grant).

### 3.8 IAM foundations + GitHub OIDC → **IAM console**
1. **EKS cluster role** `taskvault-eks-cluster-role`: trust `eks.amazonaws.com`, attach `AmazonEKSClusterPolicy`.
2. **Node role** `taskvault-eks-node-role`: trust `ec2.amazonaws.com`, attach `AmazonEKSWorkerNodePolicy`, `AmazonEC2ContainerRegistryReadOnly`, `AmazonEKS_CNI_Policy`.
3. **GitHub Actions OIDC provider:** IAM → Identity providers → Add provider → OpenID Connect → `https://token.actions.githubusercontent.com`, audience `sts.amazonaws.com`.
4. **`taskvault-github-deploy-role`:** trust the GitHub OIDC provider. *Intentionally* leave the trust condition broad (e.g. `repo:<org>/taskvault-demo:*` instead of pinning `ref:refs/heads/main` or an environment), and attach more AWS permissions than a deploy needs (ECR push + EKS update + S3 write). ← **VULN 10** cloud side. Tag it `cnapp.demo/intentional-risk=true`.

> Workload roles (`taskvault-backend-role`, `taskvault-worker-role`) are created **after** the cluster, because their trust policy references the cluster's OIDC provider — see §3.10.

### 3.9 EKS cluster + node group → **EKS console**
1. **EKS → Add cluster → Create.** Name `taskvault-eks`, latest supported K8s version, cluster role `taskvault-eks-cluster-role`.
2. Networking: `taskvault-vpc`, all four subnets, cluster SG default. Public+private endpoint access is fine for a demo.
3. Enable **control-plane logging** (api, audit, authenticator) → CloudWatch. (Audit logs feed the CNAPP's runtime evidence.)
4. After the cluster is ACTIVE: **Compute → Add node group** `taskvault-ng`, role `taskvault-eks-node-role`, **private** subnets, t3.medium ×2.
5. **Enable the OIDC provider for the cluster:** EKS → cluster → Overview copies the OIDC issuer URL; IAM → Identity providers → confirm/Add it as an OIDC provider (CDK/`eksctl` do this automatically). This is the bridge that makes IRSA work.

### 3.10 Cluster add-ons → **EKS console → Add-ons / Helm**
1. **AWS Load Balancer Controller** (installs via Helm with its own IRSA role) — turns `taskvault-public-ingress` into a real internet-facing ALB. This realizes the `Internet → ALB → Ingress → Service → Pod` chain the CNAPP graphs.
2. **EBS CSI driver** (managed add-on) — for any PVCs.
3. *(Optional, richer demo)* External Secrets Operator (syncs Secrets Manager → K8s Secret), Fluent Bit (ships pod logs to CloudWatch), Falco (runtime findings), Prometheus/Grafana.

### 3.11 Workload IAM (IRSA) → **IAM console** *(the heart of the attack path)*
Create these **after** the OIDC provider exists. Trust policy on each: federated principal = cluster OIDC provider, condition `…:sub = system:serviceaccount:demo-prod:<sa-name>`.

- **`taskvault-backend-role`** (trusts `backend-sa`):
  ```json
  { "Effect":"Allow","Action":"s3:*",
    "Resource":["arn:aws:s3:::taskvault-*","arn:aws:s3:::taskvault-*/*"] }   ← VULN 2
  { "Effect":"Allow","Action":"secretsmanager:GetSecretValue",
    "Resource":"arn:aws:secretsmanager:us-east-1:<acct>:secret:taskvault/demo/*" }  ← VULN 6
  { "Effect":"Allow","Action":["sqs:SendMessage"],"Resource":"<taskvault-jobs arn>" }
  ```
  The `s3:*` on `taskvault-*` is the over-privilege; the Secrets Manager read makes the pod a credential-pivot point.
- **`taskvault-worker-role`** (trusts `worker-sa`): `sqs:ReceiveMessage`/`DeleteMessage` on the queue, and `s3:GetObject`/`PutObject` on `taskvault-user-files/*` and `taskvault-reports/*`. (Scoped — this role is the "good contrast" against the backend role, except the worker *pod* is the one that's privileged at the K8s layer.)

### 3.12 Observability & finding sources → **CloudWatch / CloudTrail / Inspector / Security Hub**
1. **CloudWatch Logs:** log groups `/taskvault/backend`, `/taskvault/worker`, `/taskvault/frontend`, plus the EKS control-plane group. Fluent Bit or the awslogs driver ships pod stdout here.
2. **CloudTrail:** create a trail (management + S3 data events on `taskvault-user-files`) → S3 + CloudWatch. This is what shows `AssumeRole` (IRSA) and S3 object access as identity/session evidence.
3. **Amazon Inspector v2:** enable ECR scanning — generates the CVE finding for **VULN 8** that the CNAPP correlates with runtime.
4. *(Optional)* **GuardDuty** (EKS + S3 protection) and **Security Hub** (normalized findings) to demo CNAPP ingestion of native AWS findings.

---

## 4. Kubernetes environment

All objects live in namespace `demo-prod`, all carry the standard labels:
```yaml
labels:
  app.kubernetes.io/name: taskvault
  app.kubernetes.io/component: <frontend|backend-api|worker>
  app.kubernetes.io/part-of: taskvault-demo
  app.kubernetes.io/managed-by: github-actions
  cnapp.demo/environment: demo-prod
```
Risky objects additionally carry `cnapp.demo/intentional-risk: "true"` and a `…/risk-id` matching §7.

### 4.1 Object inventory
- **Namespace:** `demo-prod`
- **ServiceAccounts:** `frontend-sa`, `backend-sa` (IRSA→backend-role), `worker-sa` (IRSA→worker-role), `db-migrator-sa`, `report-job-sa`, *(opt)* `admin-sa`
- **Deployments:** `frontend`, `backend-api`, `worker`, *(opt)* `admin-api`, `notification-worker`
- **Services (ClusterIP):** `frontend-service`, `backend-service`, `worker-internal-service`, `metrics-service` *(opt)*, `admin-service` *(opt)*
- **Ingress:** `taskvault-public-ingress` (ALB, internet-facing)
- **RBAC:** `backend-secret-reader` Role + binding (VULN 3), `worker-job-reader` Role + binding, `app-config-reader` Role + binding, *(opt high-risk)* `demo-overbroad-reader` ClusterRole + binding
- **Secrets (fake):** `db-credentials`, `app-secret`, `fake-api-key`, *(opt)* `admin-bootstrap-secret`
- **ConfigMaps:** `app-config`, `feature-flags`, `frontend-config`, `backend-config`, `worker-config`
- **NetworkPolicies:** `allow-frontend-to-backend`, `allow-backend-to-rds`, `allow-backend-to-sqs`, `allow-worker-to-sqs` — **and intentionally NO `default-deny-ingress`/`default-deny-egress`** (VULN 7)
- **Jobs:** `db-migrator`, `report-job`; **CronJob:** `report-cronjob`
- **Volumes:** configMap / secret / emptyDir (normal) + **hostPath `/` on worker** (VULN 5)

### 4.2 Key manifests (vulnerabilities embedded inline)

**`k8s/serviceaccounts.yaml`** — IRSA bridge (VULN 6):
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: backend-sa
  namespace: demo-prod
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::<ACCT>:role/taskvault-backend-role
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: worker-sa
  namespace: demo-prod
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::<ACCT>:role/taskvault-worker-role
```

**`k8s/rbac.yaml`** — backend can read Secrets (VULN 3):
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata: { name: backend-secret-reader, namespace: demo-prod,
            labels: { cnapp.demo/intentional-risk: "true", cnapp.demo/risk-id: "vuln-3" } }
rules:
  - apiGroups: [""]
    resources: ["secrets"]
    verbs: ["get", "list"]      # ← over-broad: backend should never enumerate secrets
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata: { name: backend-secret-reader-binding, namespace: demo-prod }
subjects: [{ kind: ServiceAccount, name: backend-sa, namespace: demo-prod }]
roleRef: { kind: Role, name: backend-secret-reader, apiGroup: rbac.authorization.k8s.io }
```

**`k8s/backend-deployment.yaml`** — runs as root (VULN 8 runtime half):
```yaml
spec:
  template:
    spec:
      serviceAccountName: backend-sa
      containers:
        - name: backend-api
          image: <ACCT>.dkr.ecr.us-east-1.amazonaws.com/taskvault-backend:latest
          securityContext:
            runAsUser: 0            # ← root  (VULN 8)
            # no readOnlyRootFilesystem, no drop capabilities
          ports: [{ containerPort: 8080 }]
          livenessProbe:  { httpGet: { path: /api/healthz, port: 8080 } }
          readinessProbe: { httpGet: { path: /api/readyz,  port: 8080 } }
          # (resource limits intentionally omitted on at least one workload)
```

**`k8s/worker-deployment.yaml`** — privileged + hostPath (VULN 5):
```yaml
metadata:
  labels: { cnapp.demo/intentional-risk: "true", cnapp.demo/risk-id: "vuln-5" }
spec:
  template:
    spec:
      serviceAccountName: worker-sa
      containers:
        - name: worker
          image: <ACCT>.dkr.ecr.us-east-1.amazonaws.com/taskvault-worker:latest
          securityContext:
            privileged: true        # ← host escape precondition (VULN 5)
          volumeMounts: [{ name: host-root, mountPath: /host }]
      volumes:
        - name: host-root
          hostPath: { path: / }     # ← mounts node root (VULN 5)
```

**`k8s/ingress.yaml`** — public ALB + unauth route (VULN 1):
```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: taskvault-public-ingress
  namespace: demo-prod
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
spec:
  rules:
    - http:
        paths:
          - { path: /,                  pathType: Prefix, backend: { service: { name: frontend-service, port: { number: 80 } } } }
          - { path: /api,               pathType: Prefix, backend: { service: { name: backend-service,  port: { number: 8080 } } } }
          - { path: /api/debug/status,  pathType: Prefix, backend: { service: { name: backend-service,  port: { number: 8080 } } } }  # ← unauth (VULN 1)
```

**`k8s/networkpolicies.yaml`** — note what is *absent* (VULN 7): include the four `allow-*` policies but **deliberately omit** `default-deny-ingress` and `default-deny-egress`, and give worker/backend unrestricted egress. Document the omission in `docs/intentional-risks.md` so it reads as intentional, not forgotten.

**`k8s/secrets.fake.yaml`** — fake values only:
```yaml
apiVersion: v1
kind: Secret
metadata: { name: db-credentials, namespace: demo-prod }
stringData:
  DATABASE_URL: "postgres://demo:demo-not-a-real-password@taskvault-db:5432/taskvault"
---
apiVersion: v1
kind: Secret
metadata: { name: fake-api-key, namespace: demo-prod }
stringData:
  FAKE_STRIPE_SECRET_KEY: "sk_test_fake_demo_value"
```

### 4.3 Kubernetes API surface the CNAPP connector must be able to query
Core (`namespaces, nodes, pods, services, endpoints, serviceaccounts, secrets, configmaps, events, pv, pvc`), `discovery.k8s.io/endpointslices`, `apps/v1` (`deployments, replicasets, daemonsets, statefulsets`), `batch/v1` (`jobs, cronjobs`), `networking.k8s.io/v1` (`ingresses, networkpolicies`), `rbac.authorization.k8s.io/v1` (`roles, rolebindings, clusterroles, clusterrolebindings`), `admissionregistration.k8s.io/v1` (`validating/mutating webhooks`), `storage.k8s.io/v1` (`storageclasses, csidrivers, csinodes`), `metrics.k8s.io/v1beta1` (if metrics-server). The demo must actually create enough of these objects for the connector to exercise each path — EndpointSlices matter because they expose the real pod IPs behind `backend-service`.

---

## 5. GitHub environment

### 5.1 Repo layout
```
taskvault-demo/
  README.md  Makefile  docker-compose.local.yml  .env.example   ← fake secret (VULN 4)
  frontend/   { package.json, Dockerfile, src/ }
  backend/    { package.json, Dockerfile, src/, test/fixtures/ }
  worker/     { package.json, Dockerfile, src/ }
  infra/cdk/  { bin/, lib/, test/, package.json, cdk.json }
  k8s/        { namespace, serviceaccounts, rbac, secrets.fake, configmaps,
                *-deployment, services, ingress, networkpolicies, pod-security-labels }
  .github/workflows/ { build.yml, deploy.yml, security-scan.yml }
  scripts/    { seed-demo-data.ts, export-evidence.sh, validate-demo.sh }
  docs/       { architecture, graph-contract, threat-model, intentional-risks,
                test-plan, runbook, cleanup }
  artifacts/sample/ { trivy/grype/sbom/checkov/gitleaks/kubescape + expected-*.json }
```

### 5.2 `.env.example` — fake committed secret (VULN 4)
```dotenv
# DEMO ONLY — fake, dead values. Never put real credentials here.
FAKE_AWS_ACCESS_KEY_ID=AKIAFAKEDEMO123456
FAKE_STRIPE_SECRET_KEY=sk_test_fake_demo_value
DATABASE_URL=postgres://demo:password@localhost:5432/taskvault
```
*(Optional second placement: a `backend/test/fixtures/fake-secrets.txt` baked into one image layer so container/image scanning also flags it. Pure fixture, never read by app code.)*

### 5.3 Dockerfiles — image risk (VULN 8 build half)
- `backend/Dockerfile`: start from an **intentionally outdated base** (e.g. `node:16-alpine`) and pin **one** known-vulnerable dependency in `backend/package.json` (e.g. an old `lodash`/`express`). **No `USER` instruction** → container runs as root, reinforcing the `runAsUser: 0` in the deployment. Keep the vulnerable dep present-but-unused — detection/correlation is the goal, not exploitation.
- `frontend/Dockerfile`, `worker/Dockerfile`: normal multi-stage builds (contrast).

### 5.4 Workflows
- **`build.yml`** — sane baseline: build → test → `docker build` → push to ECR (OIDC into `taskvault-github-deploy-role`). This is the legit code→image edge.
- **`security-scan.yml`** — runs Trivy/Grype (image), Checkov (CDK/IaC), Gitleaks (secrets), Kubescape (manifests) and **uploads results to `artifacts/sample/`**. Intentionally **does not gate** deploy on results (no scan-gate, no image signing) — that *absence* is part of VULN 10's story.
- **`deploy.yml`** — the weak one (VULN 10):
  ```yaml
  permissions: write-all                    # ← over-broad (VULN 10)
  jobs:
    deploy:
      runs-on: ubuntu-latest
      steps:
        - uses: actions/checkout@v4
        - uses: some-org/some-deploy-action@main   # ← unpinned third-party action (VULN 10)
        - name: Assume AWS + deploy to EKS         # uses taskvault-github-deploy-role (over-privileged, VULN 10)
  ```
  Document both the `write-all` and the `@main` pin as intentional in `docs/intentional-risks.md`.

---

## 6. Infrastructure-as-Code (CDK TypeScript) — the artifact of record

`infra/cdk/lib/` should contain one stack per concern so the code connector maps file → resource → finding cleanly:

| File | Creates | Carries vuln |
|---|---|---|
| `network-stack.ts` | VPC, subnets, IGW, NAT, route tables, SGs | (VULN 7 SG egress `0.0.0.0/0` optional) |
| `ecr-stack.ts` | 3 ECR repos, scan-on-push | — |
| `storage-stack.ts` | S3 buckets, **versioning disabled** on `taskvault-user-files`, KMS | **VULN 9** |
| `rds-stack.ts` | RDS Postgres, subnet group, `taskvault-rds-sg` | — |
| `eks-stack.ts` | EKS cluster, node group, OIDC provider, ALB controller | — |
| `iam-stack.ts` | `taskvault-backend-role` (`s3:*`), `taskvault-worker-role` | **VULN 2, VULN 6** |
| `github-oidc-role.ts` | GitHub OIDC provider + `taskvault-github-deploy-role` (broad trust + perms) | **VULN 10** cloud side |
| `observability-stack.ts` | CloudWatch log groups, CloudTrail, Inspector enablement | — |

CDK can also synthesize the namespace/SA so IRSA annotations are correct, but **workload manifests stay as raw YAML under `k8s/`** so the GitHub/code connector has real files to parse.

---

## 7. The 10 intentional vulnerabilities — integration matrix

Each row: what to add, exactly where, the expected CNAPP finding, the ATT&CK technique, and the node/edge it contributes to the attack path.

| # | Detection surface | What to add | File / resource | Expected CNAPP finding | ATT&CK |
|---|---|---|---|---|---|
| 1 | Internet-facing API exposure | Public ALB ingress + one unauth route `/api/debug/status` (harmless metadata only) | `k8s/ingress.yaml`, `backend/src/routes/debug.ts`, `backend/src/middleware/auth.ts` | Internet-reachable backend path with weak/missing auth | T1190 |
| 2 | Cloud identity / permission abuse | `s3:*` on `arn:aws:s3:::taskvault-*` | `infra/cdk/lib/iam-stack.ts` | Workload IAM role has excessive data-store access | T1078.004 |
| 3 | K8s identity / RBAC escalation | `backend-sa` can `get/list secrets` in `demo-prod` | `k8s/rbac.yaml` | Service account can enumerate K8s Secrets | T1098.006 |
| 4 | Secrets / credential exposure | Fake AWS-style key + fake token committed (+ opt image layer) | `.env.example`, `backend/test/fixtures/fake-secrets.txt`, opt `backend/Dockerfile` | Secret detected in repo/container layer | T1552.001 |
| 5 | Pod-to-node / container escape | Worker pod `privileged: true` + `hostPath: /` | `k8s/worker-deployment.yaml` | Pod has host-escape preconditions | T1611 |
| 6 | AWS workload credential pivot | `backend-sa` → IRSA role with `s3:*` + `secretsmanager:GetSecretValue` on `taskvault/demo/*` | `k8s/serviceaccounts.yaml`, `iam-stack.ts`, `eks-stack.ts` | Pod compromise → AWS credential/data access | T1552.005 |
| 7 | Network segmentation / egress | No `default-deny` NetworkPolicy; broad backend/worker egress | `k8s/networkpolicies.yaml` (omission), opt SG egress `0.0.0.0/0` | Namespace permits broad east-west + outbound | T1046 |
| 8 | Image / runtime software risk | Outdated base image + one vulnerable dep + runs as root | `backend/package.json`, `backend/Dockerfile`, `k8s/backend-deployment.yaml` | Running vulnerable image is internet-exposed | (CVE/CWE class) |
| 9 | Data-store exposure | `taskvault-user-files` versioning disabled + `uploads/sensitive/*` fixtures | `infra/cdk/lib/storage-stack.ts`, `scripts/seed-demo-data.ts` | Sensitive store, weak protection, reachable by workload role | T1530 |
| 10 | CI/CD / supply-chain | `permissions: write-all` + unpinned `@main` action + over-broad OIDC deploy role | `.github/workflows/deploy.yml`, `infra/cdk/lib/github-oidc-role.ts` | CI/CD can modify repo/deploy + assumes broad AWS role | T1195.002 |

### Sensitive fixtures (synthetic, never real)
`uploads/sensitive/payroll-export-demo.csv`, `customer-records-demo.csv`, `internal-access-review-demo.csv` — a handful of obviously-fake rows each. Their realistic *names* are what let the CNAPP classify the bucket as a sensitive data store; the *contents* are harmless.

---

## 8. The master attack path & toxic combinations

This is the one explainable chain the demo exists to produce — every node has real evidence from a different connector (GitHub, K8s, AWS, scanners, runtime/CloudTrail):

```
Internet
 → Public ALB (internet-facing, no WAF)                         [AWS]      VULN 1
 → taskvault-public-ingress                                     [K8s]      VULN 1
 → backend-service → EndpointSlice → backend-api Pod            [K8s]
 → vulnerable + root backend container image                    [scanner]  VULN 8
 → backend-sa                                                    [K8s]
 → IRSA → taskvault-backend-role                                 [AWS]      VULN 6 bridge
 → s3:* on taskvault-* + secretsmanager:GetSecretValue          [AWS]      VULN 2 / 6
 → taskvault-user-files (versioning off) / uploads/sensitive/*  [AWS]      VULN 9
```

**Highest-priority toxic combination (what should rank Critical):**
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
Secondary paths to show prioritization: GitHub leaked-key (4) → IAM-shaped credential; CI/CD (10) `write-all` + unpinned action → OIDC role → EKS/ECR takeover; privileged worker (5) + no NetworkPolicy (7) → pod→node→cloud pivot.

The teaching point baked in: a lone CVE (8) or a lone `s3:*` (2) is *medium*; it becomes *critical* only when exposure + runtime + identity + sensitive data line up. That's exactly what the matrix in §7 lets the CNAPP demonstrate.

---

## 9. Evidence & graph contract (so the demo survives teardown)

`make export-evidence` writes, under `artifacts/sample/`:
- Inventories: `aws-inventory.json`, `k8s-inventory.json`, `github-inventory.json`
- Scanner outputs: `trivy-backend.json`, `grype-backend.json`, `sbom-backend.spdx.json`, `checkov.json`, `gitleaks.json`, `kubescape.json`
- Expected graph fixtures: `expected-nodes.json`, `expected-edges.json`, `expected-findings.json`, `expected-attack-paths.json`

These let the CNAPP be validated even when the live AWS environment is destroyed, and they double as the *acceptance oracle* — the CNAPP's output should match `expected-attack-paths.json`.

### Make targets
`local-up`, `local-down`, `docker-build`, `scan-local`, `cdk-synth`, `cdk-deploy`, `k8s-deploy`, `seed-demo`, `test-demo`, `export-evidence`, `destroy`.

### `scripts/validate-demo.sh` checks
namespace exists → workloads up → `backend-sa` has the IRSA role-arn annotation → `kubectl auth can-i list secrets --as=system:serviceaccount:demo-prod:backend-sa` returns **yes** (proves VULN 3) → ingress/ALB present → `aws s3api get-bucket-versioning` shows disabled (proves VULN 9) → `/api/healthz` 200 → scanner + expected-path artifacts exist.

---

## 10. Build order (phased, ~15 days)

1. **Design + local app (d1–3):** repo, three services, endpoints, audit logs, `.env.example` (VULN 4), `docker-compose.local.yml`, `make seed-demo`.
2. **Containers + local K8s (d4–6):** Dockerfiles (VULN 8 base/dep + root), all `k8s/` manifests incl. RBAC (3), worker hostPath (5), ingress (1), missing default-deny (7); validate on kind/minikube.
3. **CDK infra (d7–9):** network, ECR, storage (VULN 9), RDS, IAM (VULN 2/6), github-oidc (VULN 10 cloud), observability.
4. **EKS deploy (d10–12):** cluster + node group + OIDC, ALB controller, IRSA wiring (6), push images, deploy manifests, confirm `Internet→ALB→…→S3` path is live, logs flowing.
5. **Risks + scanners + contract (d13–15):** finalize all 10 vulns, run Trivy/Grype/Checkov/Gitleaks/Kubescape into `artifacts/`, write `expected-*.json`, `docs/intentional-risks.md`, `validate-demo.sh`, and `make destroy`.

**Acceptance:** a fresh engineer can deploy from the README; app runs locally and on EKS; ALB exposes frontend/backend; backend reaches S3 via IRSA; the main attack path exists; scanner + expected-graph artifacts exist; cleanup destroys everything; **no real secrets anywhere.**

---

## 11. Safety & cleanup (keep the lab a lab)

- Dedicated account, single region, no peering, Block Public Access on the real buckets, RDS private.
- All fake credentials are dead; `gitleaks` in CI exists partly to *prove* nothing real ever lands.
- Label every intentional risk in-cluster and document it — so an auditor (or the CNAPP) can tell "intentional demo risk" from "real mistake."
- `make destroy` runs `cdk destroy` (removing EKS/RDS/S3/VPC/IAM) and deletes ECR images, so the vulnerable surface doesn't linger and accrue cost or exposure.