#!/usr/bin/env bash
# T163 — Verify CloudWatch / audit API contains required event_types from spec §2.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAMESPACE="${K8S_NAMESPACE:-demo-prod}"
REGION="${AWS_REGION:-us-east-1}"
ADMIN_EMAIL="${DEMO_ADMIN_EMAIL:-admin@taskvault.demo}"
ADMIN_PASSWORD="${DEMO_ADMIN_PASSWORD:-password123}"
EVIDENCE_DIR="${EVIDENCE_DIR:-$REPO_ROOT/artifacts/sample}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ | tr '[:upper:]' '[:lower:]')"
EVIDENCE_FILE="${EVIDENCE_DIR}/eks-audit-coverage-${STAMP}.txt"

REQUIRED_EVENTS=(
  login_success
  login_failure
  task_created
  file_uploaded
  s3_object_written
  worker_job_created
  worker_job_started
  worker_job_completed
  admin_report_requested
  admin_report_written
)

mkdir -p "$EVIDENCE_DIR"
exec > >(tee "$EVIDENCE_FILE") 2>&1

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

ALB_HOST="$(kubectl -n "$NAMESPACE" get ingress taskvault-public-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
[[ -n "$ALB_HOST" ]] || fail "ALB hostname not ready"
BACKEND_URL="http://${ALB_HOST}"

echo "=== T163 — audit log coverage ==="

# Generate login_failure for coverage.
curl -sf -X POST "${BACKEND_URL}/api/auth/login" \
  -H 'Content-Type: application/json' \
  -d '{"email":"audit-coverage@taskvault.demo","password":"wrong-password"}' >/dev/null || true

# Generate task_created.
REGISTER="$(
  curl -sf -X POST "${BACKEND_URL}/api/auth/register" \
    -H 'Content-Type: application/json' \
    -d '{"email":"audit-task-'$(date +%s)'@taskvault.demo","password":"password12345"}'
)"
TOKEN="$(python3 -c "import json,sys; print(json.load(sys.stdin)['token'])" <<<"$REGISTER")"
curl -sf -X POST "${BACKEND_URL}/api/tasks" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H 'Content-Type: application/json' \
  -d '{"title":"Audit coverage task","description":"demo"}' >/dev/null

ADMIN_LOGIN="$(
  curl -sf -X POST "${BACKEND_URL}/api/auth/login" \
    -H 'Content-Type: application/json' \
    -d "{\"email\":\"${ADMIN_EMAIL}\",\"password\":\"${ADMIN_PASSWORD}\"}"
)"
ADMIN_TOKEN="$(python3 -c "import json,sys; print(json.load(sys.stdin)['token'])" <<<"$ADMIN_LOGIN")"

AUDIT_RESPONSE="$(
  curl -sf -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    "${BACKEND_URL}/api/admin/audit-events?limit=500"
)"

MISSING=0
for EVENT_TYPE in "${REQUIRED_EVENTS[@]}"; do
  if python3 -c "import json,sys; events=json.load(sys.stdin); sys.exit(0 if any(e.get('event_type')=='${EVENT_TYPE}' for e in events) else 1)" \
    <<<"$AUDIT_RESPONSE"; then
    echo "✓ ${EVENT_TYPE}"
  else
    echo "✗ missing: ${EVENT_TYPE}"
    MISSING=$((MISSING + 1))
  fi
done

echo ""
echo "--- CloudWatch sample (/taskvault/backend) ---"
EVENTS="$(aws logs filter-log-events \
  --region "$REGION" \
  --log-group-name /taskvault/backend \
  --filter-pattern '{ $.event_type = "file_uploaded" }' \
  --limit 3 \
  --query 'events[*].message' \
  --output text 2>/dev/null || true)"
if [[ -n "$EVENTS" && "$EVENTS" != "None" ]]; then
  echo "$EVENTS" | head -2
  echo "✓ CloudWatch contains structured audit lines"
else
  echo "WARN: no matching CloudWatch events yet (Fluent Bit may need more time)"
fi

[[ "$MISSING" -eq 0 ]] || fail "${MISSING} required event_type(s) missing from audit API"
echo ""
echo "✓ T163 audit coverage passed. Evidence: ${EVIDENCE_FILE}"
