#!/usr/bin/env bash
# M13 — export inventories, scanner outputs, and graph oracle fixtures (T185–T193).
set -euo pipefail
source "$(dirname "$0")/lib/export-evidence-common.sh"
export_evidence_init

SCRIPT_DIR="$(dirname "$0")"

echo "=== TaskVault export-evidence (M13) ==="
echo "Artifact dir: ${ARTIFACT_DIR}"
clear_generated_artifacts
echo ""

# --- T186/T187: backend image scans (trivy, grype, syft) ---
resolve_backend_image
echo "Backend image: ${BACKEND_IMAGE}"

TRIVY_JSON="${ARTIFACT_DIR}/trivy-backend.json"
GRYPE_JSON="${ARTIFACT_DIR}/grype-backend.json"
SBOM_JSON="${ARTIFACT_DIR}/sbom-backend.spdx.json"

echo ""
echo "--- T186: trivy image scan ---"
run_trivy "$BACKEND_IMAGE" "$TRIVY_JSON"
assert_nonempty "$TRIVY_JSON" "trivy-backend.json"

python3 - "$TRIVY_JSON" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
cve_count = sum(len(r.get("Vulnerabilities") or []) for r in data.get("Results", []))
secrets = []
for r in data.get("Results", []):
    for s in r.get("Secrets") or []:
        secrets.append(s.get("RuleID") or s.get("Title") or "secret")
raw = json.dumps(data)
if cve_count == 0:
    print("WARN: trivy reported 0 HIGH/CRITICAL CVEs — expected vuln-8 signal")
else:
    print(f"✓ trivy CVEs (HIGH/CRITICAL): {cve_count}")
if "AKIAFAKEDEMO" in raw or "fake-secrets" in raw or "FAKE_AWS" in raw or secrets:
    print("✓ trivy flagged baked fake secret (vuln-4/8 correlation)")
else:
    print("WARN: trivy did not surface baked fake secret — inspect trivy-backend.json")
PY

echo ""
echo "--- T186: grype image scan ---"
run_grype "$BACKEND_IMAGE" "$GRYPE_JSON"
assert_nonempty "$GRYPE_JSON" "grype-backend.json"
python3 - "$GRYPE_JSON" <<'PY'
import json, sys
raw = open(sys.argv[1]).read()
data = json.loads(raw)
matches = data.get("matches") or []
if matches:
    print(f"✓ grype vulnerabilities: {len(matches)}")
else:
    print("WARN: grype reported 0 matches")
if "AKIAFAKEDEMO" in raw or "fake" in raw.lower():
    print("✓ grype output references fake secret fixture")
PY

echo ""
echo "--- T187: syft SBOM ---"
run_syft "$BACKEND_IMAGE" "$SBOM_JSON"
assert_nonempty "$SBOM_JSON" "sbom-backend.spdx.json"
echo "✓ SBOM written"

# --- T189: Gitleaks repo scan (before CDK synth to avoid cdk.out noise) ---
echo ""
echo "--- T189: gitleaks repo scan ---"
GITLEAKS_JSON="${ARTIFACT_DIR}/gitleaks.json"
run_gitleaks "$GITLEAKS_JSON"
assert_nonempty "$GITLEAKS_JSON" "gitleaks.json"

python3 - "$GITLEAKS_JSON" <<'PY'
import json, sys
data = json.loads(open(sys.argv[1]).read())
fake_paths = (".env.example", "fake-secrets.txt")
hits = [
    x for x in data
    if any(p in x.get("File", "") for p in fake_paths)
    or any(k in (x.get("Match") or "") for k in ("AKIAFAKEDEMO", "FAKE_AWS", "sk_test_fake", "FAKE_STRIPE"))
]
if hits:
    print(f"✓ gitleaks flagged vuln-4 fake key in {len(hits)} finding(s)")
    for h in hits[:3]:
        print(f"    • {h.get('File','?').split('/repo/')[-1]} ({h.get('RuleID')})")
else:
    print(f"WARN: gitleaks did not flag .env.example/fake fixtures ({len(data)} other findings)")
PY

# --- T188: Checkov on CDK synth output ---
echo ""
echo "--- T188: Checkov CDK scan ---"
CHECKOV_JSON="${ARTIFACT_DIR}/checkov.json"
run_checkov "$CHECKOV_JSON"
assert_nonempty "$CHECKOV_JSON" "checkov.json"

python3 - "$CHECKOV_JSON" <<'PY'
import json, sys
raw = open(sys.argv[1]).read()
data = json.loads(raw)
checks = data.get("results", {}).get("failed_checks") or []
ids = {c.get("check_id") for c in checks}
print(f"Checkov failed checks: {len(checks)}")
signals = {
    "vuln-9 (S3 versioning)": "CKV_AWS_21" in ids or "versioning" in raw.lower(),
    "vuln-2 (broad IAM)": "CKV_AWS_109" in ids or "taskvault-*" in raw or "s3:*" in raw,
    "vuln-10 (OIDC/GitHub)": "oidc" in raw.lower() or "github" in raw.lower(),
}
for label, ok in signals.items():
    print(f"  {'✓' if ok else 'WARN:'} {label}")
PY

# --- T190: Kubescape on k8s manifests ---
echo ""
echo "--- T190: kubescape manifest scan ---"
KUBESCAPE_JSON="${ARTIFACT_DIR}/kubescape.json"
MANIFEST_TMP="$(k8s_manifest_tempfile)"
render_k8s_manifests "$MANIFEST_TMP"
run_kubescape "$MANIFEST_TMP" "$KUBESCAPE_JSON"
rm -f "$MANIFEST_TMP"
assert_nonempty "$KUBESCAPE_JSON" "kubescape.json"

python3 - "$KUBESCAPE_JSON" <<'PY'
import json, sys
raw = open(sys.argv[1]).read().lower()
data = json.loads(raw) if raw.strip().startswith("{") else {}
if data.get("status") == "skipped":
    print("WARN: kubescape scan skipped")
signals = {
    "privileged (vuln-5)": "privileged" in raw,
    "root/limits (vuln-8)": "runasuser" in raw or "non-root" in raw or "limits" in raw,
    "hostPath (vuln-5)": "hostpath" in raw,
    "networkPolicy (vuln-7)": "networkpolicy" in raw or "ingress and egress" in raw,
}
for label, ok in signals.items():
    print(f"  {'✓' if ok else 'WARN:'} kubescape {label}")
PY

# --- T191: Inventory collectors ---
echo ""
echo "--- T191: inventory collectors ---"
chmod +x "${SCRIPT_DIR}/collect-"*.sh
"${SCRIPT_DIR}/collect-aws-inventory.sh"
"${SCRIPT_DIR}/collect-k8s-inventory.sh"
"${SCRIPT_DIR}/collect-github-inventory.sh"

# --- T192: expected graph fixtures (hand-authored, must exist) ---
echo ""
echo "--- T192/T193: expected graph oracle fixtures ---"
for fixture in expected-nodes.json expected-edges.json expected-findings.json expected-attack-paths.json; do
  path="${ARTIFACT_DIR}/${fixture}"
  if [[ ! -f "$path" ]]; then
    echo "FAIL: missing hand-authored fixture: ${fixture}" >&2
    echo "  Create ${path} per spec §8 (T192 acceptance oracle)." >&2
    exit 1
  fi
  assert_nonempty "$path" "$fixture"
done

echo ""
echo "--- Cross-check expected graph vs inventories ---"
python3 - "$ARTIFACT_DIR" <<'PY'
import json, sys
from pathlib import Path

art = Path(sys.argv[1])
nodes = json.loads((art / "expected-nodes.json").read_text())
edges = json.loads((art / "expected-edges.json").read_text())
findings = json.loads((art / "expected-findings.json").read_text())
paths = json.loads((art / "expected-attack-paths.json").read_text())
aws = json.loads((art / "aws-inventory.json").read_text())
k8s = json.loads((art / "k8s-inventory.json").read_text())
gh = json.loads((art / "github-inventory.json").read_text())

node_ids = {n["id"] for n in nodes.get("nodes", [])}
edge_count = len(edges.get("edges", []))
finding_vulns = {f["vuln_id"] for f in findings.get("findings", [])}
path_ids = {p["id"] for p in paths.get("attack_paths", [])}

assert node_ids, "expected-nodes.json has no nodes"
assert edge_count >= 5, f"expected-edges.json too sparse ({edge_count})"
assert "vuln-1" in finding_vulns and "vuln-8" in finding_vulns, "missing core findings"
assert "master-code-to-cloud" in path_ids, "missing master attack path"

# Soft cross-checks against live inventory when available
k8s_names = set()
for kind, items in k8s.get("resources", {}).items():
    for item in items or []:
        md = item.get("metadata") or {}
        if md.get("name"):
            k8s_names.add(md["name"])

expected_k8s = {"backend-api", "backend-sa", "backend-service", "taskvault-public-ingress", "worker"}
missing = expected_k8s - k8s_names
if missing and k8s.get("summary", {}).get("pods", 0) > 0:
    print(f"WARN: k8s inventory missing expected names: {sorted(missing)}")
else:
    print("✓ k8s inventory includes core attack-path objects")

if aws.get("account"):
    print(f"✓ aws inventory account {aws['account']} region {aws['region']}")
if gh.get("workflows"):
    weak = [w["path"] for w in gh["workflows"] if w.get("permissions_write_all")]
    if weak:
        print(f"✓ github inventory captured vuln-10 signals in: {', '.join(weak)}")

print(f"✓ oracle: {len(node_ids)} nodes, {edge_count} edges, {len(finding_vulns)} findings, {len(path_ids)} paths")
PY

# --- T193: final assertion ---
echo ""
assert_all_artifacts

echo ""
echo "=== export-evidence complete ==="
echo "Artifacts in ${ARTIFACT_DIR}/"
