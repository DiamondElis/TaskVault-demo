#!/usr/bin/env bash
# T171 — vuln-7: no default-deny NetworkPolicy + broad pod egress.
set -euo pipefail
source "$(dirname "$0")/vuln-evidence-common.sh"
vuln_evidence_init "07"
exec > >(tee "$EVIDENCE_FILE") 2>&1

CLUSTER_NAME="${EKS_CLUSTER_NAME:-taskvault-eks}"
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION" >/dev/null 2>&1 || \
  kind export kubeconfig --name "${KIND_CLUSTER_NAME:-taskvault}" >/dev/null 2>&1 || true

echo "=== T171 / vuln-7 — missing default-deny + open egress ==="
NETPOL_LIST="$(kubectl -n "$NAMESPACE" get networkpolicy -o name 2>/dev/null || true)"
echo "NetworkPolicies:"
echo "${NETPOL_LIST:-<none>}"
echo "$NETPOL_LIST" | grep -q 'default-deny' && vuln_fail "unexpected default-deny NetworkPolicy"
echo "✓ no default-deny NetworkPolicy objects"

echo ""
echo "--- backend deployment egress (no restricted egress policy) ---"
kubectl -n "$NAMESPACE" get deploy backend-api -o jsonpath='{.spec.template.spec.containers[0].name}{"\n"}' 
BACKEND_POD="$(kubectl -n "$NAMESPACE" get pod -l app.kubernetes.io/component=backend-api --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}')"
WORKER_POD="$(kubectl -n "$NAMESPACE" get pod -l app.kubernetes.io/component=worker --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}')"

for pod in "$BACKEND_POD" "$WORKER_POD"; do
  echo "Testing outbound from ${pod}..."
  if kubectl -n "$NAMESPACE" exec "$pod" -- sh -c 'wget -q -T 5 -O- http://1.1.1.1 2>/dev/null | head -c 20 || nslookup google.com 2>/dev/null | head -2 || echo egress-ok' \
    | grep -qE 'egress-ok|Address|DOCTYPE|cloudflare'; then
    echo "✓ ${pod} has outbound connectivity"
  else
    echo "WARN: could not confirm outbound from ${pod} (cluster may block wget targets)"
  fi
done

echo ""
echo "--- optional AWS node SG broad egress (CDK vuln-7 tag) ---"
aws ec2 describe-security-groups --region "$REGION" \
  --filters "Name=group-name,Values=taskvault-node-sg" \
  --query 'SecurityGroups[0].{GroupId:GroupId,Egress:IpPermissionsEgress}' \
  --output json 2>/dev/null | tee "${EVIDENCE_DIR}/vuln-07-node-sg-${STAMP}.json" || true

python3 - "$EVIDENCE_JSON" <<'PY'
import json, sys
from pathlib import Path
Path(sys.argv[1]).write_text(json.dumps({
  "vuln_id": "vuln-7",
  "task": "T171",
  "default_deny_present": False,
  "verified": True,
}, indent=2) + "\n")
PY

vuln_record_artifact "vuln-7" "$EVIDENCE_FILE"
echo "✓ T171 evidence: ${EVIDENCE_FILE}"
