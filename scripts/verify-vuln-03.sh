#!/usr/bin/env bash
# T167 — vuln-3: backend-sa can list secrets in demo-prod.
set -euo pipefail
source "$(dirname "$0")/vuln-evidence-common.sh"
vuln_evidence_init "03"
exec > >(tee "$EVIDENCE_FILE") 2>&1

CLUSTER_NAME="${EKS_CLUSTER_NAME:-taskvault-eks}"
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION" >/dev/null 2>&1 || true

echo "=== T167 / vuln-3 — backend-sa secret enumeration ==="
RBAC_CMD="kubectl auth can-i list secrets --as=system:serviceaccount:${NAMESPACE}:backend-sa -n ${NAMESPACE}"
echo "$RBAC_CMD"
RBAC_OUT="$($RBAC_CMD)"
echo "=> ${RBAC_OUT}"
[[ "$RBAC_OUT" == "yes" ]] || vuln_fail "backend-sa cannot list secrets"

echo ""
echo "--- RoleBinding evidence ---"
kubectl -n "$NAMESPACE" get role,rolebinding -l cnapp.demo/risk-id=vuln-3 -o wide 2>/dev/null || \
  kubectl -n "$NAMESPACE" get role backend-secret-reader rolebinding backend-secret-reader-binding -o yaml

FEATURE_FLAG="$(kubectl -n "$NAMESPACE" get configmap feature-flags -o jsonpath='{.data.FEATURE_K8S_SECRET_LIST}' 2>/dev/null || echo false)"
echo ""
echo "FEATURE_K8S_SECRET_LIST=${FEATURE_FLAG}"
if [[ "$FEATURE_FLAG" == "true" ]]; then
  ALB_HOST="$(vuln_alb_host)"
  if [[ -n "$ALB_HOST" ]]; then
    ADMIN_EMAIL="${DEMO_ADMIN_EMAIL:-admin@taskvault.demo}"
    ADMIN_PASSWORD="${DEMO_ADMIN_PASSWORD:-password123}"
    TOKEN="$(curl -sf -X POST "http://${ALB_HOST}/api/auth/login" \
      -H 'Content-Type: application/json' \
      -d "{\"email\":\"${ADMIN_EMAIL}\",\"password\":\"${ADMIN_PASSWORD}\"}" \
      | python3 -c "import json,sys; print(json.load(sys.stdin)['token'])")"
    echo "--- GET /api/admin/internal/k8s-secret-names (names only) ---"
    curl -sf -H "Authorization: Bearer ${TOKEN}" "http://${ALB_HOST}/api/admin/internal/k8s-secret-names" \
      | tee "${EVIDENCE_DIR}/vuln-03-secret-names-${STAMP}.json"
  fi
else
  echo "Live secret-name demo skipped (FEATURE_K8S_SECRET_LIST=false). RBAC can-i is sufficient evidence."
fi

python3 - "$EVIDENCE_JSON" <<'PY'
import json, sys
from pathlib import Path
Path(sys.argv[1]).write_text(json.dumps({
  "vuln_id": "vuln-3",
  "task": "T167",
  "rbac_can_i_list_secrets": "yes",
  "verified": True,
}, indent=2) + "\n")
PY

vuln_record_artifact "vuln-3" "$EVIDENCE_FILE"
echo "✓ T167 evidence: ${EVIDENCE_FILE}"
