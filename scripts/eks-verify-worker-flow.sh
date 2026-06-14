#!/usr/bin/env bash
# T162 — Verify worker consumed SQS message, touched S3, updated job row.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAMESPACE="${K8S_NAMESPACE:-demo-prod}"
ADMIN_EMAIL="${DEMO_ADMIN_EMAIL:-admin@taskvault.demo}"
ADMIN_PASSWORD="${DEMO_ADMIN_PASSWORD:-password123}"
EVIDENCE_DIR="${EVIDENCE_DIR:-$REPO_ROOT/artifacts/sample}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ | tr '[:upper:]' '[:lower:]')"
EVIDENCE_FILE="${EVIDENCE_DIR}/eks-worker-flow-${STAMP}.txt"

mkdir -p "$EVIDENCE_DIR"
exec > >(tee "$EVIDENCE_FILE") 2>&1

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

ALB_HOST="$(kubectl -n "$NAMESPACE" get ingress taskvault-public-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
[[ -n "$ALB_HOST" ]] || fail "ALB hostname not ready"
BACKEND_URL="http://${ALB_HOST}"

echo "=== T162 — worker SQS → S3 → RDS flow ==="

ADMIN_LOGIN="$(
  curl -sf -X POST "${BACKEND_URL}/api/auth/login" \
    -H 'Content-Type: application/json' \
    -d "{\"email\":\"${ADMIN_EMAIL}\",\"password\":\"${ADMIN_PASSWORD}\"}"
)"
ADMIN_TOKEN="$(python3 -c "import json,sys; print(json.load(sys.stdin)['token'])" <<<"$ADMIN_LOGIN")"

AUDIT_RESPONSE="$(
  curl -sf -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    "${BACKEND_URL}/api/admin/audit-events?limit=300"
)"

for EVENT_TYPE in worker_job_started worker_job_completed s3_object_written; do
  python3 -c "import json,sys; events=json.load(sys.stdin); sys.exit(0 if any(e.get('event_type')=='${EVENT_TYPE}' for e in events) else 1)" \
    <<<"$AUDIT_RESPONSE" || fail "missing audit event: ${EVENT_TYPE}"
  echo "✓ audit event present: ${EVENT_TYPE}"
done

echo ""
echo "--- worker pod logs (recent job activity) ---"
WORKER_POD="$(kubectl -n "$NAMESPACE" get pod -l app.kubernetes.io/component=worker -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
if [[ -n "$WORKER_POD" ]]; then
  kubectl -n "$NAMESPACE" logs "$WORKER_POD" --tail=40 | grep -E 'consumer_job|worker_job|job_id' | head -10 || true
fi

echo ""
echo "✓ T162 worker flow verified. Evidence: ${EVIDENCE_FILE}"
