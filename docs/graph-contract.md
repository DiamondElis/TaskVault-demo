# Graph contract

This document defines the node types, edge types, findings, and attack paths a CNAPP should produce when ingesting TaskVault. The **acceptance oracle** is the set of hand-authored fixtures under `artifacts/sample/` generated and validated by `make export-evidence`.

| Fixture | Purpose |
|---|---|
| [`expected-nodes.json`](../artifacts/sample/expected-nodes.json) | Canonical graph nodes |
| [`expected-edges.json`](../artifacts/sample/expected-edges.json) | Relationships between nodes |
| [`expected-findings.json`](../artifacts/sample/expected-findings.json) | Posture / vulnerability findings |
| [`expected-attack-paths.json`](../artifacts/sample/expected-attack-paths.json) | Prioritized attack paths and toxic combinations |

Live inventories (`aws-inventory.json`, `k8s-inventory.json`, `github-inventory.json`) and scanner outputs provide corroborating evidence when the environment is up. Expected fixtures survive teardown.

---

## Schema version

All fixtures declare `"schema_version": "1.0"`. CNAPP output should be matchable on:

- Stable logical `id` fields (not environment-specific ARNs)
- `vuln_ids` arrays linking nodes/findings/paths to demo risks
- `canonical_names` / `label` for cross-walking live inventory

---

## Node types

Each node in `expected-nodes.json`:

```json
{
  "id": "k8s-pod-backend-api",
  "type": "pod",
  "provider": "kubernetes",
  "label": "backend-api",
  "namespace": "demo-prod",
  "vuln_ids": ["vuln-8"],
  "connectors": ["k8s", "scanner"]
}
```

| `type` | `provider` | Description | Example `id` |
|---|---|---|---|
| `exposure` | `external` | Off-cloud entry point | `internet` |
| `load_balancer` | `aws` | Internet-facing ALB | `aws-alb-public` |
| `ingress` | `kubernetes` | K8s Ingress resource | `k8s-ingress-taskvault-public` |
| `service` | `kubernetes` | ClusterIP Service | `k8s-service-backend` |
| `endpointslice` | `kubernetes` | Pod endpoints behind a Service | `k8s-endpointslice-backend` |
| `pod` | `kubernetes` | Running workload | `k8s-pod-backend-api`, `k8s-pod-worker` |
| `serviceaccount` | `kubernetes` | Pod identity | `k8s-sa-backend` |
| `container_image` | `ecr` | Built artifact | `container-image-backend` |
| `iam_role` | `aws` | IAM role (IRSA or OIDC) | `aws-iam-backend-role`, `aws-iam-github-oidc-role` |
| `s3_bucket` | `aws` | S3 bucket | `aws-s3-user-files` |
| `s3_object_prefix` | `aws` | Sensitive prefix within bucket | `aws-s3-sensitive-prefix` |
| `repository` | `github` | Source repo | `github-repo-taskvault` |
| `workflow` | `github` | GitHub Actions workflow | `github-workflow-deploy` |

**Required node count (oracle):** 15 nodes in `expected-nodes.json`.

---

## Edge types

Each edge in `expected-edges.json`:

```json
{
  "id": "sa-irsa-backend-role",
  "from": "k8s-sa-backend",
  "to": "aws-iam-backend-role",
  "relationship": "assumes_via_irsa",
  "vuln_ids": ["vuln-6"]
}
```

| `relationship` | Meaning |
|---|---|
| `exposes` | Untrusted network reachability |
| `routes_to` | L7/L4 routing (ALB → Ingress → Service) |
| `selects` | Service selector → EndpointSlice |
| `targets` | EndpointSlice → Pod IP |
| `runs` | Pod runs container image |
| `uses_serviceaccount` | PodSpec serviceAccountName |
| `assumes_via_irsa` | K8s SA annotated with `eks.amazonaws.com/role-arn` |
| `s3_star_access` | IAM policy grants broad S3 |
| `contains` | Bucket contains object prefix |
| `builds` | CI builds and pushes image |
| `assumes_via_oidc` | GitHub OIDC → IAM role |
| `lateral_pivot_potential` | Secondary pivot edge (worker → cloud) |

**Required edge count (oracle):** ≥ 13 edges.

---

## Findings

Each finding in `expected-findings.json`:

```json
{
  "id": "finding-vuln-8-vulnerable-root-image",
  "vuln_id": "vuln-8",
  "title": "Vulnerable root backend container (node:16-alpine + CVEs)",
  "severity": "medium",
  "source": "scanner",
  "signals": ["node:16-alpine", "lodash 4.17.15", "runAsUser: 0", "trivy CVE"],
  "node_ids": ["container-image-backend", "k8s-pod-backend-api"]
}
```

| Field | Description |
|---|---|
| `vuln_id` | One of `vuln-1` … `vuln-10` |
| `severity` | Demo-relative: `medium`, `high`; toxic combo elevates to `critical` in paths |
| `source` | `aws`, `kubernetes`, `github`, `scanner` |
| `signals` | Evidence strings a CNAPP should surface |
| `node_ids` | Graph nodes the finding attaches to |

**Required findings (oracle):** one finding per vuln (`vuln-1` through `vuln-10`).

Scanner corroboration (from `make export-evidence`):

| Finding | Scanner artifact | Signal |
|---|---|---|
| vuln-4 | `gitleaks.json`, `trivy-backend.json` | Fake key patterns, image layer |
| vuln-8 | `trivy-backend.json`, `grype-backend.json` | CVEs, root base image |
| vuln-9 | `checkov.json` | `CKV_AWS_21` |
| vuln-2 | `checkov.json` | `CKV_AWS_109`, broad IAM |
| vuln-3/5/7/8 | `kubescape.json` | privileged, hostPath, limits, netpol |

---

## Attack paths

Each path in `expected-attack-paths.json`:

```json
{
  "id": "master-code-to-cloud",
  "priority": "critical",
  "title": "Internet → ALB → vulnerable root backend → IRSA → broad S3 + sensitive data",
  "toxic_combination": true,
  "vuln_ids": ["vuln-1", "vuln-8", "vuln-3", "vuln-6", "vuln-2", "vuln-9", "vuln-7"],
  "techniques": ["T1190", "T1078", "T1552", "T1530"],
  "node_sequence": ["internet", "aws-alb-public", "..."],
  "edge_sequence": ["internet-to-alb", "..."],
  "finding_ids": ["finding-vuln-1-alb-exposure", "..."],
  "narrative": "..."
}
```

| Path `id` | Priority | Description |
|---|---|---|
| `master-code-to-cloud` | **critical** | Primary teaching chain (toxic combination) |
| `secondary-github-leak-to-iam` | high | vuln-4 secret scanning correlation |
| `secondary-cicd-oidc-takeover` | high | vuln-10 supply chain |
| `secondary-worker-node-pivot` | medium | vuln-5 + vuln-7 lateral movement |

**Acceptance criterion:** CNAPP output should reproduce `master-code-to-cloud` with the same ordered `node_sequence` (logical IDs may map to environment-specific ARNs/hostnames).

---

## Validation workflow

```bash
# Export live evidence + assert oracle fixtures exist
make export-evidence

# Cross-check graph vs live inventory (built into export-evidence)
# Manual spot-check:
jq '.nodes | length' artifacts/sample/expected-nodes.json
jq '.attack_paths[] | select(.id=="master-code-to-cloud") | .node_sequence' artifacts/sample/expected-attack-paths.json
```

After teardown, validate CNAPP output against `expected-*.json` only. Scanner and inventory files in `artifacts/sample/` may be regenerated from a fresh deploy.

---

## Connector coverage map

| Connector | Nodes fed | Evidence |
|---|---|---|
| AWS | ALB, IAM, S3, RDS, CloudTrail | `aws-inventory.json`, CloudFormation |
| Kubernetes | Ingress, Service, EndpointSlice, Pod, SA, RBAC | `k8s-inventory.json` |
| GitHub | Repo, workflows, Dockerfiles | `github-inventory.json` |
| Scanners | Container image, IaC, secrets, manifests | `trivy-backend.json`, `checkov.json`, etc. |
| Runtime / logs | Audit events, CloudTrail IRSA usage | CloudWatch `/taskvault/*`, `make eks-verify-irsa-s3` |

See [architecture.md](architecture.md) for topology and [threat-model.md](threat-model.md) for ATT&CK mapping.
