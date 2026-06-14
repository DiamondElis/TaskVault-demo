#!/usr/bin/env bash
# T184 — Verify CI pipeline: build artifacts, deploy image SHA, scanner outputs.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

OWNER_REPO="${GITHUB_REPOSITORY:-}"
RUN_ID="${GITHUB_RUN_ID:-}"
EXPECTED_SHA="${EXPECTED_SHA:-${GITHUB_SHA:-}}"
NAMESPACE="${K8S_NAMESPACE:-demo-prod}"
EVIDENCE_DIR="${EVIDENCE_DIR:-$REPO_ROOT/artifacts/sample}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ | tr '[:upper:]' '[:lower:]')"
EVIDENCE_FILE="${EVIDENCE_DIR}/ci-pipeline-verify-${STAMP}.txt"

mkdir -p "$EVIDENCE_DIR"
exec > >(tee "$EVIDENCE_FILE") 2>&1

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

echo "=== T184 — CI/CD pipeline verification ==="

if [[ -n "$OWNER_REPO" ]] && command -v gh >/dev/null 2>&1; then
  echo "--- GitHub Actions workflow runs (latest on main) ---"
  gh run list --repo "$OWNER_REPO" --branch main --limit 6 || true
  if [[ -n "$RUN_ID" ]]; then
    echo ""
    echo "--- Run ${RUN_ID} jobs ---"
    gh run view "$RUN_ID" --repo "$OWNER_REPO" || true
    echo ""
    echo "--- Security-scan artifacts ---"
    gh run download "$RUN_ID" --repo "$OWNER_REPO" -n "security-scan-${EXPECTED_SHA}" -D "${EVIDENCE_DIR}/ci-scan-${STAMP}" 2>/dev/null || \
      echo "WARN: security-scan artifact not found for run ${RUN_ID}"
  fi
else
  echo "Set GITHUB_REPOSITORY + gh CLI for remote workflow verification."
  echo "Local checklist:"
  echo "  1. Push to main triggers build.yml, security-scan.yml, deploy.yml"
  echo "  2. build.yml pushes taskvault-* images tagged with \${{ github.sha }}"
  echo "  3. security-scan.yml uploads trivy/grype/sbom/gitleaks/checkov/kubescape artifacts"
  echo "  4. deploy.yml applies overlays/eks with matching image tag"
fi

if [[ -n "$EXPECTED_SHA" ]] && kubectl get deploy backend-api -n "$NAMESPACE" >/dev/null 2>&1; then
  echo ""
  echo "--- EKS deployment image tag ---"
  RUNNING="$(kubectl -n "$NAMESPACE" get deploy backend-api -o jsonpath='{.spec.template.spec.containers[0].image}')"
  echo "backend-api image: ${RUNNING}"
  echo "$RUNNING" | grep -q "${EXPECTED_SHA}" || fail "running image does not contain expected SHA ${EXPECTED_SHA}"
  echo "✓ running image matches commit SHA"
fi

echo ""
echo "Evidence: ${EVIDENCE_FILE}"
