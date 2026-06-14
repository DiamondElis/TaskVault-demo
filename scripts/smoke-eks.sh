#!/usr/bin/env bash
# T160 — End-to-end flow via ALB: register → login → upload → process → admin report.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAMESPACE="${K8S_NAMESPACE:-demo-prod}"
ADMIN_EMAIL="${DEMO_ADMIN_EMAIL:-admin@taskvault.demo}"
ADMIN_PASSWORD="${DEMO_ADMIN_PASSWORD:-password123}"
POLL_SECONDS="${SMOKE_POLL_SECONDS:-120}"
EVIDENCE_DIR="${EVIDENCE_DIR:-$REPO_ROOT/artifacts/sample}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ | tr '[:upper:]' '[:lower:]')"
EVIDENCE_FILE="${EVIDENCE_DIR}/eks-e2e-${STAMP}.txt"

mkdir -p "$EVIDENCE_DIR"
exec > >(tee "$EVIDENCE_FILE") 2>&1

json_field() {
  local payload="$1"
  local field="$2"
  python3 -c "import json,sys; print(json.load(sys.stdin)['$field'])" <<<"$payload"
}

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

ALB_HOST="${BACKEND_URL#http://}"
ALB_HOST="${ALB_HOST#https://}"
ALB_HOST="${ALB_HOST%%/*}"
if [[ -z "$ALB_HOST" || "$ALB_HOST" == "http:"* ]]; then
  ALB_HOST="$(kubectl -n "$NAMESPACE" get ingress taskvault-public-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
fi
[[ -n "$ALB_HOST" ]] || fail "could not resolve ALB hostname"
BACKEND_URL="http://${ALB_HOST}"

echo "=== T160 — EKS end-to-end via ALB (${BACKEND_URL}) ==="

SMOKE_EMAIL="smoke-$(date +%s)@taskvault.demo"
SMOKE_PASSWORD="smoke-pass-12345678"
CSV_FILE="$(mktemp /tmp/taskvault-eks-smoke-XXXXXX-demo.csv)"
trap 'rm -f "$CSV_FILE"' EXIT

cat >"$CSV_FILE" <<'EOF'
employee_id,name,amount
1,Demo User,1000
2,Demo User,1200
EOF

echo "Registering smoke user ${SMOKE_EMAIL}..."
REGISTER_RESPONSE="$(
  curl -sf -X POST "${BACKEND_URL}/api/auth/register" \
    -H 'Content-Type: application/json' \
    -d "{\"email\":\"${SMOKE_EMAIL}\",\"password\":\"${SMOKE_PASSWORD}\"}"
)"
TOKEN="$(json_field "$REGISTER_RESPONSE" token)"

echo "Logging in smoke user..."
LOGIN_RESPONSE="$(
  curl -sf -X POST "${BACKEND_URL}/api/auth/login" \
    -H 'Content-Type: application/json' \
    -d "{\"email\":\"${SMOKE_EMAIL}\",\"password\":\"${SMOKE_PASSWORD}\"}"
)"
TOKEN="$(json_field "$LOGIN_RESPONSE" token)"
AUTH_HEADER="Authorization: Bearer ${TOKEN}"

echo "Uploading sensitive demo CSV..."
UPLOAD_RESPONSE="$(
  curl -sf -X POST "${BACKEND_URL}/api/files/upload" \
    -H "$AUTH_HEADER" \
    -F "file=@${CSV_FILE};type=text/csv" \
    -F "classification=sensitive"
)"
FILE_ID="$(json_field "$UPLOAD_RESPONSE" file_id)"

echo "Triggering file processing for ${FILE_ID}..."
PROCESS_RESPONSE="$(
  curl -sf -X POST "${BACKEND_URL}/api/files/${FILE_ID}/process" \
    -H "$AUTH_HEADER"
)"
JOB_ID="$(json_field "$PROCESS_RESPONSE" id)"
echo "Job ${JOB_ID} queued."

echo "Polling job status (timeout ${POLL_SECONDS}s)..."
DEADLINE=$((SECONDS + POLL_SECONDS))
JOB_STATUS="queued"
while (( SECONDS < DEADLINE )); do
  FILES_RESPONSE="$(curl -sf -H "$AUTH_HEADER" "${BACKEND_URL}/api/files")"
  JOB_STATUS="$(
    python3 -c "import json,sys; files=json.load(sys.stdin); print(next((f.get('latest_job_status') for f in files if f.get('file_id')=='${FILE_ID}'), 'unknown'))" \
      <<<"$FILES_RESPONSE"
  )"
  if [[ "$JOB_STATUS" == "completed" ]]; then
    break
  fi
  if [[ "$JOB_STATUS" == "failed" ]]; then
    fail "job ${JOB_ID} failed"
  fi
  sleep 3
done
[[ "$JOB_STATUS" == "completed" ]] || fail "timed out waiting for job ${JOB_ID} (last status: ${JOB_STATUS})"
echo "✓ worker completed job ${JOB_ID}"

echo "Running admin report..."
ADMIN_LOGIN="$(
  curl -sf -X POST "${BACKEND_URL}/api/auth/login" \
    -H 'Content-Type: application/json' \
    -d "{\"email\":\"${ADMIN_EMAIL}\",\"password\":\"${ADMIN_PASSWORD}\"}"
)"
ADMIN_TOKEN="$(json_field "$ADMIN_LOGIN" token)"
REPORT_RESPONSE="$(
  curl -sf -X POST "${BACKEND_URL}/api/admin/reports/run" \
    -H "Authorization: Bearer ${ADMIN_TOKEN}"
)"
echo "$REPORT_RESPONSE" | python3 -c "import json,sys; data=json.load(sys.stdin); print('report_id=', data.get('report',{}).get('id','?'))"

echo ""
echo "✓ T160 EKS end-to-end passed. Evidence: ${EVIDENCE_FILE}"
