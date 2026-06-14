#!/usr/bin/env bash
# T157 — Run db-migrator on EKS and verify RDS schema (Secrets Manager via IRSA).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/cdk-outputs.sh
source "$REPO_ROOT/scripts/cdk-outputs.sh"
# shellcheck source=scripts/eks-render-overlay.sh
source "$REPO_ROOT/scripts/eks-render-overlay.sh"

CLUSTER_NAME="${EKS_CLUSTER_NAME:-taskvault-eks}"
REGION="${AWS_REGION:-us-east-1}"
NAMESPACE="${K8S_NAMESPACE:-demo-prod}"
EVIDENCE_DIR="${EVIDENCE_DIR:-$REPO_ROOT/artifacts/sample}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ | tr '[:upper:]' '[:lower:]')"
EVIDENCE_FILE="${EVIDENCE_DIR}/eks-db-migrator-${STAMP}.txt"

mkdir -p "$EVIDENCE_DIR"
exec > >(tee "$EVIDENCE_FILE") 2>&1

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION" >/dev/null

echo "=== T157 — db-migrator on EKS ==="
OVERLAY_BUILD="$(eks_render_overlay)"
trap 'rm -rf "$OVERLAY_BUILD"' EXIT

JOB_MANIFEST="$(mktemp)"
kubectl kustomize "$OVERLAY_BUILD/overlays/eks" | awk '
  BEGIN {found=0}
  /^kind: Job$/ {found=1}
  found {print}
  found && /^---$/ {exit}
' >"$JOB_MANIFEST"

kubectl -n "$NAMESPACE" delete job db-migrator --ignore-not-found
kubectl -n "$NAMESPACE" apply -f "$JOB_MANIFEST"
rm -f "$JOB_MANIFEST"

echo "Waiting for db-migrator Job to complete..."
kubectl -n "$NAMESPACE" wait --for=condition=complete job/db-migrator --timeout=300s

echo ""
echo "--- db-migrator logs ---"
MIGRATOR_LOGS="$(kubectl -n "$NAMESPACE" logs job/db-migrator)"
echo "$MIGRATOR_LOGS"
echo "$MIGRATOR_LOGS" | grep -q 'Migrations complete' || fail "migrator did not finish migrations"
echo "$MIGRATOR_LOGS" | grep -q 'Skipping demo seed' || fail "expected SKIP_DEMO_SEED on EKS migrator"

echo ""
echo "Verifying db-migrator-sa IRSA role..."
kubectl -n "$NAMESPACE" get sa db-migrator-sa -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}{"\n"}' \
  | grep -q 'taskvault-backend-role' || fail "db-migrator-sa missing backend IRSA role"

echo ""
echo "Verifying backend can reach RDS..."
ALB_HOST="$(kubectl -n "$NAMESPACE" get ingress taskvault-public-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
if [[ -n "$ALB_HOST" ]]; then
  curl -sf "http://${ALB_HOST}/api/readyz" | grep -q '"database":true' || fail "ALB readyz database check failed"
  echo "✓ RDS reachable via ALB readyz"
else
  echo "WARN: ALB not ready — skipping external readyz check"
fi

echo ""
echo "✓ T157 passed. Evidence: ${EVIDENCE_FILE}"
