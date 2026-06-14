#!/usr/bin/env bash
# T147 — Deploy EKS stack and configure kubeconfig.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT/infra/cdk"

CLUSTER_NAME="${EKS_CLUSTER_NAME:-taskvault-eks}"
REGION="${AWS_REGION:-${CDK_DEFAULT_REGION:-us-east-1}}"

npm install
npm run build

echo "Deploying EKS stack (cluster, node group, ALB controller, EBS CSI, Fluent Bit)..."
npx cdk deploy TaskvaultEks --require-approval never

echo "Updating kubeconfig for ${CLUSTER_NAME}..."
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION"

echo ""
kubectl get nodes -o wide
echo ""
echo "EKS deploy complete. Next: make eks-verify && make cdk-deploy-iam"
