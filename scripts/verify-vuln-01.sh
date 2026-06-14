#!/usr/bin/env bash
# T165 — vuln-1: internet-exposed unauthenticated debug routes (metadata only).
set -euo pipefail
source "$(dirname "$0")/vuln-evidence-common.sh"
vuln_evidence_init "01"
exec > >(tee "$EVIDENCE_FILE") 2>&1

ALB_HOST="$(vuln_alb_host)"
[[ -n "$ALB_HOST" ]] || vuln_fail "ALB hostname not available — run after T155"
BASE="http://${ALB_HOST}"

echo "=== T165 / vuln-1 — unauthenticated ALB routes ==="
echo "Target: ${BASE}"
echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""

for path in /api/debug/status /api/admin/reports/preview; do
  echo "--- REQUEST: GET ${BASE}${path} (no Authorization header) ---"
  RESPONSE="$(curl -si "${BASE}${path}" 2>&1)"
  echo "$RESPONSE"
  STATUS="$(echo "$RESPONSE" | head -1)"
  BODY="$(echo "$RESPONSE" | awk 'BEGIN{body=0} body{print} /^$/{body=1}')"
  echo "$STATUS" | grep -q ' 200 ' || vuln_fail "${path} did not return HTTP 200"
  echo "$BODY" | grep -qiE 'password|secret|token|jwt|AKIA|sk_test' && vuln_fail "${path} body may contain secrets"
  echo "✓ ${path} returned 200 with metadata-only body"
  echo ""
done

python3 - "$EVIDENCE_FILE" "$EVIDENCE_JSON" <<'PY'
import json, sys
from pathlib import Path
txt, out = sys.argv[1:3]
Path(out).write_text(json.dumps({
  "vuln_id": "vuln-1",
  "task": "T165",
  "artifact_txt": txt,
  "routes": ["/api/debug/status", "/api/admin/reports/preview"],
  "verified": True,
}, indent=2) + "\n")
PY

vuln_record_artifact "vuln-1" "$EVIDENCE_FILE"
echo "✓ T165 evidence: ${EVIDENCE_FILE}"
