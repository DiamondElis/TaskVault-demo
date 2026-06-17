# Threat model

TaskVault is an **intentionally weak** demo environment. This document maps each of the ten demo vulnerabilities to MITRE ATT&CK techniques, the file/resource that introduces them, and the trust boundaries they cross.

Evidence matrix: [`artifacts/sample/vuln-matrix-latest.json`](../artifacts/sample/vuln-matrix-latest.json). Attack-path oracle: [`expected-attack-paths.json`](../artifacts/sample/expected-attack-paths.json).

---

## Trust boundaries

```
┌─────────────────────────────────────────────────────────────────────────┐
│  UNTRUSTED: Internet                                                    │
└───────────────────────────────┬─────────────────────────────────────────┘
                                │  TB-1: Internet → ALB (no WAF, 0.0.0.0/0)
                                ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  SEMI-TRUSTED: EKS data plane (demo-prod namespace)                     │
│  • Ingress → Service → Pod                                              │
│  • Weak RBAC (backend-sa lists Secrets)                                 │
│  • No default-deny NetworkPolicy                                        │
│  • Privileged worker pod + hostPath                                     │
└───────────────────────────────┬─────────────────────────────────────────┘
                                │  TB-2: Pod → cloud (IRSA WebIdentity)
                                ▼
┌─────────────────────────────────────────────────────────────────────────┐
│  TRUSTED (over-permissioned): AWS account taskvault-demo-prod           │
│  • taskvault-backend-role: s3:* + Secrets Manager read                  │
│  • taskvault-github-deploy-role: broad CI/CD access                     │
│  • Sensitive S3 prefixes, RDS, Secrets Manager                          │
└─────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────┐
│  TB-3: GitHub → AWS (OIDC) — CI/CD can assume deploy role from any ref  │
└─────────────────────────────────────────────────────────────────────────┘
```

| Boundary | From | To | Primary vulns | What breaks |
|---|---|---|---|---|
| **TB-1** | Internet | ALB → backend Pod | vuln-1, vuln-8 | Unauthenticated reachability to weak backend on vulnerable image |
| **TB-2** | Compromised pod | AWS APIs (S3, Secrets Manager) | vuln-2, vuln-3, vuln-6 | Pod SA + IRSA → broad data access |
| **TB-3** | GitHub Actions | EKS / ECR / S3 | vuln-10 | Supply-chain compromise → cloud takeover |
| **TB-4** | Worker pod | Node host | vuln-5, vuln-7 | Privileged + hostPath + permissive egress |
| **TB-5** | Source repo | Runtime | vuln-4 | Fake credentials in repo/image layers |

---

## Vulnerability → ATT&CK → location

| ID | ATT&CK | Technique name | Introduced by | Expected CNAPP finding |
|---|---|---|---|---|
| **vuln-1** | [T1190](https://attack.mitre.org/techniques/T1190/) | Exploit Public-Facing Application | `k8s/base/ingress.yaml` (internet-facing ALB); `backend/src/routes/debug.ts` (`GET /api/debug/status` — no auth) | Internet-reachable backend with weak/missing auth |
| **vuln-2** | [T1078.004](https://attack.mitre.org/techniques/T1078/004/) | Valid Accounts: Cloud Accounts | `infra/cdk/lib/iam-stack.ts` — `s3:*` on `arn:aws:s3:::taskvault-*` | Workload IAM role has excessive S3 access |
| **vuln-3** | [T1098.006](https://attack.mitre.org/techniques/T1098/006/) | Account Manipulation: Additional Container Cluster Roles | `k8s/base/rbac.yaml` — `backend-secret-reader` Role lets `backend-sa` get/list Secrets | Service account can enumerate K8s Secrets |
| **vuln-4** | [T1552.001](https://attack.mitre.org/techniques/T1552/001/) | Unsecured Credentials: Credentials In Files | `.env.example`; `backend/test/fixtures/fake-secrets.txt`; `backend/Dockerfile` (COPY fixture layer) | Secret detected in repo / container image |
| **vuln-5** | [T1611](https://attack.mitre.org/techniques/T1611/) | Escape to Host | `k8s/base/worker-deployment.yaml` — `privileged: true`, `hostPath: /` | Pod has container-escape preconditions |
| **vuln-6** | [T1552.005](https://attack.mitre.org/techniques/T1552/005/) | Unsecured Credentials: Cloud Instance Metadata API | `k8s/base/serviceaccounts.yaml` (IRSA annotation) + `infra/cdk/lib/iam-stack.ts` (role trust + Secrets Manager) | Pod compromise → AWS credential / secret access |
| **vuln-7** | [T1046](https://attack.mitre.org/techniques/T1046/) | Network Service Discovery | `k8s/base/networkpolicies.yaml` — **omission** of default-deny; only `allow-*` policies | Namespace permits broad east-west and outbound traffic |
| **vuln-8** | CVE/CWE class | Vulnerable software + misconfiguration | `backend/Dockerfile` (`node:16-alpine`, no USER); `backend/package.json` (`lodash@4.17.15`); `k8s/base/backend-deployment.yaml` (`runAsUser: 0`, no limits) | Internet-exposed pod running vulnerable root container |
| **vuln-9** | [T1530](https://attack.mitre.org/techniques/T1530/) | Data from Cloud Storage | `infra/cdk/lib/storage-stack.ts` (`versioned: false`); `scripts/seed-demo-data.ts` (`uploads/sensitive/*`) | Sensitive data store with weak protection, reachable by workload role |
| **vuln-10** | [T1195.002](https://attack.mitre.org/techniques/T1195/002/) | Supply Chain Compromise: Software Supply Chain | `.github/workflows/deploy.yml` (`permissions: write-all`, `@main` action); `infra/cdk/lib/github-oidc-role-stack.ts` (broad OIDC trust) | CI/CD can modify deploy pipeline and assume over-privileged AWS role |

---

## Master attack path (threat narrative)

An external actor reaches the backend via the public ALB (**vuln-1**). The running container is outdated, runs as root, and carries known CVEs (**vuln-8**). From inside the pod, the compromised workload can:

1. List Kubernetes Secrets via `backend-sa` RBAC (**vuln-3**).
2. Use IRSA-injected credentials for `taskvault-backend-role` (**vuln-6**).
3. Exercise `s3:*` against all `taskvault-*` buckets (**vuln-2**).
4. Read/write sensitive objects under `uploads/sensitive/` where versioning is disabled (**vuln-9**).
5. Move laterally within the namespace because no default-deny NetworkPolicy exists (**vuln-7**).

A **lone** CVE or **lone** `s3:*` grant is medium severity. The demo's teaching point is that **correlation** across exposure + runtime + identity + data elevates the path to Critical — matching `expected-attack-paths.json` → `master-code-to-cloud`.

---

## Secondary paths

### GitHub secret correlation (vuln-4)

Fake `AKIAFAKEDEMO…` and `sk_test_fake_demo_value` placeholders appear in the repo and backend image layer. Scanners (Gitleaks, Trivy secret scan) should correlate these with the GitHub → ECR build edge even though values are dead.

### CI/CD supply chain (vuln-10)

`deploy.yml` uses `permissions: write-all` and an unpinned third-party action. Combined with `taskvault-github-deploy-role` trusting `repo:<org>/taskvault-demo:*`, any branch/ref can push images and mutate EKS — a separate high-priority path from runtime exploitation.

### Worker node pivot (vuln-5 + vuln-7)

The worker Deployment runs privileged with a host root mount. With permissive network egress, this demonstrates pod→node→cloud pivot scenarios that should rank below the master path but above isolated misconfigurations.

---

## Toxic combination (Critical priority)

The CNAPP should rank **Critical** when all of the following align on one explainable chain:

| Factor | Vuln |
|---|---|
| Internet exposure | 1 |
| Vulnerable running container | 8 |
| Weak K8s identity / RBAC | 3 |
| AWS workload credential bridge (IRSA) | 6 |
| Broad IAM data access | 2 |
| Sensitive S3 with weak protection | 9 |
| Weak network segmentation | 7 |

Reference: [architecture.md — Master attack path](architecture.md#master-attack-path-spec-8).

---

## What this demo does NOT include

- Real credentials, PII, or working exploit payloads
- Public S3 buckets (exposure is via workload IAM, not bucket ACLs)
- Weaponized CVE exploitation — detection and graph correlation only

See [intentional-risks.md](intentional-risks.md) for remediation guidance per vulnerability.
