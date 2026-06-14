#!/usr/bin/env bash
# T146 — Deploy foundational CDK stacks (network through observability, excluding EKS/IAM).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT/infra/cdk"

npm install
npm run build

STACKS=(
  TaskvaultNetwork
  TaskvaultKms
  TaskvaultEcr
  TaskvaultStorage
  TaskvaultRds
  TaskvaultObservability
)

echo "Deploying foundational stacks: ${STACKS[*]}"
npx cdk deploy "${STACKS[@]}" --require-approval never

echo ""
echo "Foundational stack outputs:"
for stack in "${STACKS[@]}"; do
  echo "--- ${stack} ---"
  aws cloudformation describe-stacks \
    --stack-name "$stack" \
    --region "${AWS_REGION:-us-east-1}" \
    --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' \
    --output table 2>/dev/null || true
done

echo ""
echo "Foundation deploy complete. Next: make cdk-deploy-eks"
