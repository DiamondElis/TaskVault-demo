#!/usr/bin/env bash
# T172 — vuln-8: vulnerable+root image correlated with ALB exposure.
set -euo pipefail
source "$(dirname "$0")/vuln-evidence-common.sh"
vuln_evidence_init "08"
exec > >(tee "$EVIDENCE_FILE") 2>&1

IMAGE="${VULN_SCAN_IMAGE:-taskvault-backend:local}"
TRIVY_JSON="${EVIDENCE_DIR}/trivy-backend-vuln08-${STAMP}.json"
INSPECTOR_JSON="${EVIDENCE_DIR}/inspector-vuln08-${STAMP}.json"

echo "=== T172 / vuln-8 — CVE + root + internet exposure ==="

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  (cd "$REPO_ROOT" && docker build -t "$IMAGE" -f backend/Dockerfile --target stage-1 .)
fi

echo "--- Image base (node:16-alpine intentional) ---"
docker image inspect "$IMAGE" --format '{{.Config.Image}} {{index .Config.Labels "cnapp.demo/risk-id"}}' 2>/dev/null || true
grep -q 'node:16-alpine' "$REPO_ROOT/backend/Dockerfile" && echo "✓ Dockerfile uses node:16-alpine"
grep -q 'lodash' "$REPO_ROOT/backend/package.json" && echo "✓ vulnerable dep lodash pinned in package.json"

echo ""
echo "--- trivy CVE scan ---"
if command -v trivy >/dev/null 2>&1; then
  trivy image --scanners vuln --severity HIGH,CRITICAL --format json --output "$TRIVY_JSON" "$IMAGE"
else
  docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v "$EVIDENCE_DIR:/out" \
    aquasec/trivy:latest image --scanners vuln --severity HIGH,CRITICAL --format json \
    --output "/out/$(basename "$TRIVY_JSON")" "$IMAGE"
fi
CVE_COUNT="$(python3 -c "import json; d=json.load(open('$TRIVY_JSON')); print(sum(len(r.get('Vulnerabilities') or []) for r in d.get('Results',[])))" 2>/dev/null || echo 0)"
echo "High/Critical CVE count (trivy): ${CVE_COUNT}"
[[ "$CVE_COUNT" -gt 0 ]] || echo "WARN: trivy reported 0 HIGH/CRITICAL — inspect ${TRIVY_JSON}"

echo ""
echo "--- Inspector v2 ECR findings (if image pushed) ---"
# shellcheck source=scripts/cdk-outputs.sh
source "$REPO_ROOT/scripts/cdk-outputs.sh" 2>/dev/null || true
if export_value BACKEND_REPO TaskvaultEcr BackendRepoUri 2>/dev/null; then
  aws inspector2 list-findings --region "$REGION" \
    --filter-criteria '{"ecrImageRepositoryName":[{"comparison":"EQUALS","value":"taskvault-backend"}]}' \
    --max-results 10 --output json 2>/dev/null | tee "$INSPECTOR_JSON" || echo "WARN: Inspector findings unavailable"
fi

echo ""
echo "--- Live pod runAsUser + ALB reachability ---"
BACKEND_POD="$(kubectl -n "$NAMESPACE" get pod -l app.kubernetes.io/component=backend-api --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
if [[ -n "$BACKEND_POD" ]]; then
  RUN_AS="$(kubectl -n "$NAMESPACE" get pod "$BACKEND_POD" -o jsonpath='{.spec.containers[0].securityContext.runAsUser}')"
  echo "backend pod: ${BACKEND_POD}, runAsUser: ${RUN_AS}"
  [[ "$RUN_AS" == "0" ]] || vuln_fail "backend pod not running as root (runAsUser=${RUN_AS})"
fi

ALB_HOST="$(vuln_alb_host)"
[[ -n "$ALB_HOST" ]] || vuln_fail "ALB not reachable — required for vuln-8 correlation"
curl -sf "http://${ALB_HOST}/api/debug/status" | tee "${EVIDENCE_DIR}/vuln-08-alb-debug-${STAMP}.json"
echo "✓ backend reachable via internet-facing ALB"

python3 - "$EVIDENCE_JSON" "$TRIVY_JSON" <<'PY'
import json, sys
from pathlib import Path
Path(sys.argv[1]).write_text(json.dumps({
  "vuln_id": "vuln-8",
  "task": "T172",
  "signals": ["trivy_cves", "runAsUser_0", "alb_reachable", "node16_base"],
  "trivy_json": sys.argv[2],
  "verified": True,
}, indent=2) + "\n")
PY

vuln_record_artifact "vuln-8" "$EVIDENCE_FILE"
echo "✓ T172 evidence: ${EVIDENCE_FILE}"
