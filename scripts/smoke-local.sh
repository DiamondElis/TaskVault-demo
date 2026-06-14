#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

BACKEND_URL="${BACKEND_URL:-http://localhost:8080}"
FRONTEND_URL="${FRONTEND_URL:-http://localhost:3000}"
ADMIN_EMAIL="${DEMO_ADMIN_EMAIL:-admin@taskvault.demo}"
ADMIN_PASSWORD="${DEMO_ADMIN_PASSWORD:-password123}"
POLL_SECONDS="${SMOKE_POLL_SECONDS:-90}"

json_field() {
  local payload="$1"
  local field="$2"
  python3 -c "import json,sys; print(json.load(sys.stdin)['$field'])" <<<"$payload"
}

json_nested() {
  local payload="$1"
  local expr="$2"
  python3 -c "import json,sys; data=json.load(sys.stdin); print($expr)" <<<"$payload"
}

require_http() {
  local url="$1"
  curl -sf "$url" >/dev/null
}

echo "TaskVault local end-to-end smoke test"
if [[ "${SKIP_LOCAL_UP:-}" != "1" ]]; then
  echo "Bringing up docker compose stack..."
  make local-up
else
  echo "Skipping compose bring-up (SKIP_LOCAL_UP=1)."
fi

echo "Running basic health checks..."
BACKEND_URL="$BACKEND_URL" FRONTEND_URL="$FRONTEND_URL" ./scripts/validate-demo.sh

SMOKE_EMAIL="smoke-$(date +%s)@taskvault.demo"
SMOKE_PASSWORD="smoke-pass-12345678"
CSV_FILE="$(mktemp /tmp/taskvault-smoke-XXXXXX-demo.csv)"
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
AUTH_HEADER="Authorization: Bearer ${TOKEN}"

echo "Logging in smoke user..."
LOGIN_RESPONSE="$(
  curl -sf -X POST "${BACKEND_URL}/api/auth/login" \
    -H 'Content-Type: application/json' \
    -d "{\"email\":\"${SMOKE_EMAIL}\",\"password\":\"${SMOKE_PASSWORD}\"}"
)"
TOKEN="$(json_field "$LOGIN_RESPONSE" token)"
AUTH_HEADER="Authorization: Bearer ${TOKEN}"

echo "Uploading *-demo.csv fixture..."
UPLOAD_RESPONSE="$(
  curl -sf -X POST "${BACKEND_URL}/api/files/upload" \
    -H "$AUTH_HEADER" \
    -F "file=@${CSV_FILE};type=text/csv" \
    -F "classification=private"
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
    echo "Job failed unexpectedly."
    exit 1
  fi
  sleep 2
done

if [[ "$JOB_STATUS" != "completed" ]]; then
  echo "Timed out waiting for job ${JOB_ID} (last status: ${JOB_STATUS})."
  exit 1
fi
echo "Job ${JOB_ID} completed."

echo "Fetching presigned download URL..."
DOWNLOAD_RESPONSE="$(
  curl -sf -H "$AUTH_HEADER" "${BACKEND_URL}/api/files/${FILE_ID}/download-url"
)"
DOWNLOAD_URL="$(json_field "$DOWNLOAD_RESPONSE" url)"
# Presigned URLs use the in-compose hostname; rewrite for host-side curl.
DOWNLOAD_URL="${DOWNLOAD_URL//localstack/localhost}"
require_http "$DOWNLOAD_URL"
echo "Download URL reachable."

echo "Verifying audit events via admin API..."
ADMIN_LOGIN="$(
  curl -sf -X POST "${BACKEND_URL}/api/auth/login" \
    -H 'Content-Type: application/json' \
    -d "{\"email\":\"${ADMIN_EMAIL}\",\"password\":\"${ADMIN_PASSWORD}\"}"
)"
ADMIN_TOKEN="$(json_field "$ADMIN_LOGIN" token)"
AUDIT_RESPONSE="$(
  curl -sf -H "Authorization: Bearer ${ADMIN_TOKEN}" \
    "${BACKEND_URL}/api/admin/audit-events?limit=200"
)"

for EVENT_TYPE in login_success file_uploaded worker_job_created worker_job_completed; do
  if ! python3 -c "import json,sys; events=json.load(sys.stdin); sys.exit(0 if any(e.get('event_type')=='${EVENT_TYPE}' for e in events) else 1)" <<<"$AUDIT_RESPONSE"; then
    echo "Missing expected audit event: ${EVENT_TYPE}"
    exit 1
  fi
  echo "✓ audit event present: ${EVENT_TYPE}"
done

echo "Local end-to-end smoke test passed."
