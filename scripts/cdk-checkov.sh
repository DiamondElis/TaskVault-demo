#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CDK_DIR="${REPO_ROOT}/infra/cdk"
OUT_DIR="${CDK_DIR}/cdk.out"
EVIDENCE_DIR="${EVIDENCE_DIR:-${REPO_ROOT}/artifacts/sample}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ | tr '[:upper:]' '[:lower:]')"
CHECKOV_JSON="${EVIDENCE_DIR}/checkov-cdk-${STAMP}.json"

mkdir -p "$EVIDENCE_DIR"

cd "$CDK_DIR"
npm run build
npx cdk synth --quiet -o cdk.out

run_checkov() {
  local rc=0
  if command -v checkov >/dev/null 2>&1; then
    checkov -d "$OUT_DIR" --framework cloudformation --compact -o json >"$CHECKOV_JSON" || rc=$?
  elif docker info >/dev/null 2>&1; then
    docker run --rm -v "$OUT_DIR:/cdk.out:ro" bridgecrew/checkov:latest \
      -d /cdk.out --framework cloudformation --compact -o json >"$CHECKOV_JSON" || rc=$?
  else
    echo "checkov not found and Docker unavailable — skipping IaC scan." >&2
    return 0
  fi
  # Non-zero exit is expected when intentional demo weaknesses are flagged.
  if [[ "$rc" -ne 0 ]]; then
    echo "Checkov reported findings (exit ${rc}) — see artifact for details."
  fi
  return 0
}

echo "Running Checkov against synthesized CDK templates..."
run_checkov

if [[ -f "$CHECKOV_JSON" ]] && command -v jq >/dev/null 2>&1; then
  echo ""
  echo "Expected weakness signals (vuln-9 versioning, vuln-2 IAM, vuln-10 OIDC):"
  grep -E 'CKV_AWS_21|CKV_AWS_109|CKV_AWS_286|versioning|OIDC|taskvault-\*' "$CHECKOV_JSON" \
    | head -5 || true
  failed="$(jq '[.results.failed_checks[]?] | length' "$CHECKOV_JSON" 2>/dev/null || echo 0)"
  echo ""
  echo "Checkov failed checks: ${failed} (includes intentional demo risks + CDK custom-resource noise)"
fi

echo ""
echo "Checkov artifact: ${CHECKOV_JSON}"
