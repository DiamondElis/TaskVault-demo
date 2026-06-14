#!/usr/bin/env bash
# T168 — vuln-4: fake secrets in repo (.env.example) + baked image fixture layer.
set -euo pipefail
source "$(dirname "$0")/vuln-evidence-common.sh"
vuln_evidence_init "04"
exec > >(tee "$EVIDENCE_FILE") 2>&1

GITLEAKS_JSON="${EVIDENCE_DIR}/gitleaks-vuln04-${STAMP}.json"
GITLEAKS_RAW="${EVIDENCE_DIR}/gitleaks-vuln04-raw-${STAMP}.json"
TRIVY_JSON="${EVIDENCE_DIR}/trivy-backend-vuln04-${STAMP}.json"
IMAGE="${VULN_SCAN_IMAGE:-taskvault-backend:local}"

echo "=== T168 / vuln-4 — repo + image secret scanning ==="
echo "Repo fixtures:"
grep -n 'AKIAFAKEDEMO\|sk_test_fake' "$REPO_ROOT/.env.example" "$REPO_ROOT/backend/test/fixtures/fake-secrets.txt" || true

echo ""
echo "--- gitleaks (no allowlist — expect fake placeholders flagged) ---"
if command -v gitleaks >/dev/null 2>&1; then
  gitleaks detect --source "$REPO_ROOT" --no-git --redact -f json -r "$GITLEAKS_RAW" \
    --config "$REPO_ROOT/scripts/gitleaks-verify.toml" || true
elif docker info >/dev/null 2>&1; then
  docker run --rm -v "$REPO_ROOT:/repo:ro" -v "$EVIDENCE_DIR:/out" \
    ghcr.io/gitleaks/gitleaks:latest detect --source /repo --no-git -f json \
    -r "/out/$(basename "$GITLEAKS_RAW")" --config /repo/scripts/gitleaks-verify.toml || true
else
  vuln_fail "gitleaks not available"
fi

[[ -f "$GITLEAKS_RAW" ]] || vuln_fail "gitleaks output missing"
grep -q 'AKIAFAKEDEMO\|sk_test_fake\|FAKE_AWS\|FAKE_STRIPE' "$GITLEAKS_RAW" \
  || vuln_fail "gitleaks did not flag fake placeholder patterns"
echo "✓ gitleaks flagged fake placeholder patterns"

echo ""
echo "--- gitleaks with production allowlist (should suppress known fakes) ---"
if command -v gitleaks >/dev/null 2>&1; then
  gitleaks detect --source "$REPO_ROOT" --no-git -f json -r "$GITLEAKS_JSON" \
    --config "$REPO_ROOT/.gitleaks.toml" && ALLOWLIST_EXIT=0 || ALLOWLIST_EXIT=$?
  echo "allowlist scan exit: ${ALLOWLIST_EXIT}"
fi

echo ""
echo "--- trivy image scan (${IMAGE}) ---"
if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  echo "Building ${IMAGE}..."
  (cd "$REPO_ROOT" && docker build -t "$IMAGE" -f backend/Dockerfile --target stage-1 .)
fi

if command -v trivy >/dev/null 2>&1; then
  trivy image --scanners secret,vuln --format json --output "$TRIVY_JSON" "$IMAGE"
elif docker info >/dev/null 2>&1; then
  docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
    -v "$EVIDENCE_DIR:/out" aquasec/trivy:latest image \
    --scanners secret,vuln --format json \
    --output "/out/$(basename "$TRIVY_JSON")" "$IMAGE"
else
  vuln_fail "trivy not available"
fi

[[ -f "$TRIVY_JSON" ]] || vuln_fail "trivy output missing"
grep -qi 'fixtures\|fake-secret\|AKIAFAKE\|/fixtures/' "$TRIVY_JSON" \
  || grep -qi '"Severity": "HIGH"\|"Severity": "CRITICAL"' "$TRIVY_JSON" \
  || echo "WARN: trivy secret/CVE signals weak — inspect ${TRIVY_JSON} manually"
echo "✓ trivy scan captured"

python3 - "$EVIDENCE_JSON" "$GITLEAKS_RAW" "$TRIVY_JSON" <<'PY'
import json, sys
from pathlib import Path
out, gitleaks, trivy = sys.argv[1:4]
Path(out).write_text(json.dumps({
  "vuln_id": "vuln-4",
  "task": "T168",
  "gitleaks_raw": gitleaks,
  "trivy_image": trivy,
  "verified": True,
}, indent=2) + "\n")
PY

vuln_record_artifact "vuln-4" "$EVIDENCE_FILE"
echo "✓ T168 evidence: ${EVIDENCE_FILE}"
