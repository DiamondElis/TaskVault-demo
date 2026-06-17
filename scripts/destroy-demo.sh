#!/usr/bin/env bash
# Tear down TaskVault demo environment (EKS workloads + CDK stacks).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# shellcheck source=scripts/lib/taskvault-aws.sh
source "$REPO_ROOT/scripts/lib/taskvault-aws.sh"

CLUSTER_NAME="${EKS_CLUSTER_NAME:-taskvault-eks}"
NAMESPACE="${K8S_NAMESPACE:-demo-prod}"
CDK_DIR="${REPO_ROOT}/infra/cdk"

echo "=== TaskVault destroy ==="
echo "Profile: ${AWS_PROFILE}  Region: ${AWS_REGION}"
echo ""

if kubectl config current-context >/dev/null 2>&1; then
  echo "--- Delete namespace ${NAMESPACE} ---"
  kubectl delete namespace "$NAMESPACE" --ignore-not-found --timeout=300s || \
    echo "WARN: namespace delete timed out — ALB may still be draining"
else
  echo "WARN: kubectl not configured — skipping namespace delete"
fi

echo ""
echo "--- CDK destroy all stacks ---"
cd "$CDK_DIR"
npm run build --silent 2>/dev/null || npm run build
npx cdk destroy --all --force

echo ""
echo "=== Destroy complete ==="
echo "Verify in AWS console: no EKS cluster, RDS, S3 buckets, or taskvault-* IAM roles remain."
echo "See docs/cleanup.md for manual checklist."
