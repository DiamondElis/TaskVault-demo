#!/usr/bin/env bash
# T175 — Compile vuln-1..10 evidence into a single matrix (spec §7).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EVIDENCE_DIR="${EVIDENCE_DIR:-$REPO_ROOT/artifacts/sample}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ | tr '[:upper:]' '[:lower:]')"
MATRIX_JSON="${EVIDENCE_DIR}/vuln-matrix-${STAMP}.json"
MATRIX_MD="${EVIDENCE_DIR}/vuln-matrix-${STAMP}.md"
LATEST_JSON="${EVIDENCE_DIR}/vuln-matrix-latest.json"
DOCS_MD="${REPO_ROOT}/docs/intentional-risks.md"

mkdir -p "$EVIDENCE_DIR"

python3 - "$REPO_ROOT" "$EVIDENCE_DIR" "$MATRIX_JSON" "$MATRIX_MD" "$LATEST_JSON" "$DOCS_MD" <<'PY'
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

repo, evidence_dir, matrix_json, matrix_md, latest_json, docs_md = map(Path, sys.argv[1:7])

rows = [
    {
        "id": "vuln-1",
        "task": "T165",
        "surface": "Internet-facing API exposure",
        "what": "Public ALB + unauth /api/debug/status and /api/admin/reports/preview",
        "where": "k8s/base/ingress.yaml, backend/src/routes/debug.ts",
        "finding": "Internet-reachable backend path with weak/missing auth",
        "attack": "T1190",
    },
    {
        "id": "vuln-2",
        "task": "T166",
        "surface": "Cloud identity / permission abuse",
        "what": "s3:* on arn:aws:s3:::taskvault-*",
        "where": "infra/cdk/lib/iam-stack.ts",
        "finding": "Workload IAM role has excessive data-store access",
        "attack": "T1078.004",
    },
    {
        "id": "vuln-3",
        "task": "T167",
        "surface": "K8s identity / RBAC escalation",
        "what": "backend-sa can get/list secrets in demo-prod",
        "where": "k8s/base/rbac.yaml",
        "finding": "Service account can enumerate K8s Secrets",
        "attack": "T1098.006",
    },
    {
        "id": "vuln-4",
        "task": "T168",
        "surface": "Secrets / credential exposure",
        "what": "Fake AWS/Stripe placeholders in repo + image fixture layer",
        "where": ".env.example, backend/test/fixtures/fake-secrets.txt, backend/Dockerfile",
        "finding": "Secret detected in repo/container layer",
        "attack": "T1552.001",
    },
    {
        "id": "vuln-5",
        "task": "T169",
        "surface": "Pod-to-node / container escape",
        "what": "Worker privileged: true + hostPath: /",
        "where": "k8s/base/worker-deployment.yaml",
        "finding": "Pod has host-escape preconditions",
        "attack": "T1611",
    },
    {
        "id": "vuln-6",
        "task": "T170",
        "surface": "AWS workload credential pivot",
        "what": "backend-sa IRSA → s3:* + secretsmanager:GetSecretValue",
        "where": "k8s/base/serviceaccounts.yaml, infra/cdk/lib/iam-stack.ts",
        "finding": "Pod compromise → AWS credential/data access",
        "attack": "T1552.005",
    },
    {
        "id": "vuln-7",
        "task": "T171",
        "surface": "Network segmentation / egress",
        "what": "No default-deny NetworkPolicy; broad egress",
        "where": "k8s/base/networkpolicies.yaml (omission)",
        "finding": "Namespace permits broad east-west + outbound",
        "attack": "T1046",
    },
    {
        "id": "vuln-8",
        "task": "T172",
        "surface": "Image / runtime software risk",
        "what": "node:16-alpine + lodash + runAsUser 0 + ALB exposure",
        "where": "backend/Dockerfile, backend/package.json, k8s/base/backend-deployment.yaml",
        "finding": "Running vulnerable image is internet-exposed",
        "attack": "CVE/CWE class",
    },
    {
        "id": "vuln-9",
        "task": "T173",
        "surface": "Data-store exposure",
        "what": "S3 versioning disabled + uploads/sensitive/* fixtures",
        "where": "infra/cdk/lib/storage-stack.ts, backend/src/db/seed-demo.ts",
        "finding": "Sensitive store, weak protection, reachable by workload role",
        "attack": "T1530",
    },
    {
        "id": "vuln-10",
        "task": "T174",
        "surface": "CI/CD / supply-chain",
        "what": "permissions: write-all + @main action + broad OIDC deploy role",
        "where": ".github/workflows/deploy.yml, infra/cdk/lib/github-oidc-role-stack.ts",
        "finding": "CI/CD can modify repo/deploy + assumes broad AWS role",
        "attack": "T1195.002",
    },
]

def latest_artifact(vuln_id: str) -> str:
    matches = sorted(evidence_dir.glob(f"vuln-{vuln_id.split('-')[1]}-*.txt"), reverse=True)
    if not matches:
        matches = sorted(evidence_dir.glob(f"vuln-{vuln_id}-*.txt"), reverse=True)
    return str(matches[0].relative_to(repo)) if matches else "(not captured — run verify-vuln-matrix.sh)"

for row in rows:
    num = row["id"].split("-")[1]
    row["evidence_artifact"] = latest_artifact(row["id"]) if latest_artifact(row["id"]) else latest_artifact(f"0{num}")
    # normalize lookup by numeric suffix
    matches = sorted(evidence_dir.glob(f"vuln-{num}-*.txt"), reverse=True)
    row["evidence_artifact"] = str(matches[0].relative_to(repo)) if matches else "(pending)"

payload = {
    "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "spec_section": "README.md §7",
    "vulnerabilities": rows,
}

matrix_json.write_text(json.dumps(payload, indent=2) + "\n")
latest_json.write_text(json.dumps(payload, indent=2) + "\n")

md = [
    "# Intentional risks — verification matrix (M11 / T175)",
    "",
    f"Generated: `{payload['generated_at']}`. Mirrors [README §7](../README.md#7-the-10-intentional-vulnerabilities--integration-matrix).",
    "",
    "| # | Task | Detection surface | What to add | Where | Expected finding | ATT&CK | Evidence artifact |",
    "|---|------|-------------------|-------------|-------|------------------|--------|-------------------|",
]
for i, row in enumerate(rows, start=1):
    md.append(
        f"| {i} | {row['task']} | {row['surface']} | {row['what']} | `{row['where']}` | {row['finding']} | {row['attack']} | `{row['evidence_artifact']}` |"
    )
md.extend([
    "",
    "## Per-vulnerability notes",
    "",
])
for row in rows:
    md.extend([
        f"### {row['id']} — {row['surface']}",
        "",
        f"- **Task:** {row['task']}",
        f"- **Wiring:** `{row['where']}`",
        f"- **Proof:** `{row['evidence_artifact']}`",
        "",
    ])

matrix_md.write_text("\n".join(md) + "\n")

# Backbone for docs/intentional-risks.md — keep detailed narrative below matrix import.
header = "\n".join([
    "# Intentional risks",
    "",
    "<!-- M11 T175: matrix compiled from live verification. Regenerate: make verify-vuln-matrix -->",
    "",
    f"**Verification matrix:** see [`artifacts/sample/{matrix_md.name}`](../artifacts/sample/{matrix_md.name}) and [`vuln-matrix-latest.json`](../artifacts/sample/vuln-matrix-latest.json).",
    "",
    "## Integration matrix (spec §7)",
    "",
    "| # | ID | Task | Evidence |",
    "|---|-----|------|----------|",
])
for i, row in enumerate(rows, start=1):
    header += f"| {i} | {row['id']} | {row['task']} | `{row['evidence_artifact']}` |\n"
header += "\n"

existing = docs_md.read_text() if docs_md.exists() else ""
if "## Risk register (auditor-facing)" in existing:
    narrative = existing.split("## Risk register (auditor-facing)", 1)[1]
    docs_md.write_text(header + "\n## Risk register (auditor-facing)" + narrative)
elif "## vuln-8 —" in existing:
    narrative = existing.split("## vuln-8 —", 1)[1]
    docs_md.write_text(header + "\n## vuln-8 —" + narrative)
else:
    docs_md.write_text(header + "\n" + matrix_md.read_text())

print(f"Wrote {matrix_json}")
print(f"Wrote {matrix_md}")
print(f"Updated {docs_md}")
PY

echo "✓ T175 matrix compiled: ${MATRIX_JSON}"
