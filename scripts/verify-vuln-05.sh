#!/usr/bin/env bash
# T169 — vuln-5: privileged worker + hostPath / on live cluster.
set -euo pipefail
source "$(dirname "$0")/vuln-evidence-common.sh"
vuln_evidence_init "05"
exec > >(tee "$EVIDENCE_FILE") 2>&1

export PATH="${HOME}/.kubescape/bin:${PATH}"
CLUSTER_NAME="${EKS_CLUSTER_NAME:-taskvault-eks}"
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION" >/dev/null 2>&1 || \
  kind export kubeconfig --name "${KIND_CLUSTER_NAME:-taskvault}" >/dev/null 2>&1 || true

WORKER_POD="$(kubectl -n "$NAMESPACE" get pod -l app.kubernetes.io/component=worker \
  --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
[[ -n "$WORKER_POD" ]] || vuln_fail "no running worker pod"

POD_YAML="${EVIDENCE_DIR}/vuln-05-worker-pod-${STAMP}.yaml"
kubectl -n "$NAMESPACE" get pod "$WORKER_POD" -o yaml | tee "$POD_YAML" >/dev/null

echo "=== T169 / vuln-5 — privileged worker + hostPath ==="
privileged="$(kubectl -n "$NAMESPACE" get pod "$WORKER_POD" -o jsonpath='{.spec.containers[0].securityContext.privileged}')"
hostpath="$(kubectl -n "$NAMESPACE" get pod "$WORKER_POD" -o jsonpath='{.spec.volumes[?(@.hostPath)].hostPath.path}')"
echo "pod: ${WORKER_POD}"
echo "securityContext.privileged: ${privileged}"
echo "hostPath.path: ${hostpath}"
[[ "$privileged" == "true" ]] || vuln_fail "worker not privileged"
[[ "$hostpath" == "/" ]] || vuln_fail "worker missing hostPath /"

KUBESCAPE_JSON="${EVIDENCE_DIR}/kubescape-vuln05-${STAMP}.json"
if command -v kubescape >/dev/null 2>&1; then
  echo ""
  echo "--- kubescape (privileged container control) ---"
  kubescape scan framework nsa --include-namespaces "$NAMESPACE" \
    --format json --output "$KUBESCAPE_JSON" --submit=false 2>&1 | tail -20 || true
  grep -qi 'privileged\|Privileged' "$KUBESCAPE_JSON" 2>/dev/null && echo "✓ kubescape mentions privileged containers" \
    || echo "WARN: inspect kubescape output for privileged findings"
else
  echo "WARN: kubescape not installed — pod YAML is primary evidence"
fi

python3 - "$EVIDENCE_JSON" "$POD_YAML" <<'PY'
import json, sys
from pathlib import Path
Path(sys.argv[1]).write_text(json.dumps({
  "vuln_id": "vuln-5",
  "task": "T169",
  "worker_pod_yaml": sys.argv[2],
  "privileged": True,
  "hostPath": "/",
  "verified": True,
}, indent=2) + "\n")
PY

vuln_record_artifact "vuln-5" "$EVIDENCE_FILE"
echo "✓ T169 evidence: ${EVIDENCE_FILE}"
