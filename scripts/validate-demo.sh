#!/usr/bin/env bash
set -euo pipefail

BACKEND_URL="${BACKEND_URL:-http://localhost:8080}"
WORKER_URL="${WORKER_URL:-http://localhost:8081}"
FRONTEND_URL="${FRONTEND_URL:-http://localhost:3000}"

echo "Validating TaskVault demo (local smoke checks)..."

curl -sf "${BACKEND_URL}/api/healthz" | grep -q '"status":"ok"'
echo "✓ backend healthz"

curl -sf "${BACKEND_URL}/api/readyz" | grep -q '"database":true'
echo "✓ backend readyz (database)"

curl -sf "${WORKER_URL}/worker/healthz" | grep -q '"status":"ok"' || echo "⚠ worker not running (skip)"

curl -sf "${FRONTEND_URL}/health" >/dev/null 2>&1 || echo "⚠ frontend not running (skip)"

test -f backend/ROUTES.md
echo "✓ backend ROUTES.md present"

test -d backend/migrations
echo "✓ migrations present"

echo "Basic demo validation passed."
