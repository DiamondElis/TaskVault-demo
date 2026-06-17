#!/usr/bin/env bash
# T147 — Deploy EKS stack and configure kubeconfig.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/taskvault-aws.sh
source "$REPO_ROOT/scripts/lib/taskvault-aws.sh"
cd "$REPO_ROOT/infra/cdk"

CLUSTER_NAME="${EKS_CLUSTER_NAME:-taskvault-eks}"

chmod +x "$REPO_ROOT/scripts/cdk-eks-preflight.sh" \
  "$REPO_ROOT/scripts/eks-wait-nodes.sh" \
  "$REPO_ROOT/scripts/eks-install-alb-controller.sh" \
  "$REPO_ROOT/scripts/eks-install-cloudwatch-observability.sh"

"$REPO_ROOT/scripts/cdk-eks-preflight.sh"

npm install
npm run build

echo "Deploying EKS stack (cluster, node group, IRSA for ALB, EBS CSI, Fluent Bit)..."
echo "  ALB controller Helm install runs after nodes are Ready (not in CloudFormation)."
npx cdk deploy TaskvaultEks --require-approval never

echo "Updating kubeconfig for ${CLUSTER_NAME}..."
taskvault_eks_update_kubeconfig "$CLUSTER_NAME"

"$REPO_ROOT/scripts/eks-wait-nodes.sh"
"$REPO_ROOT/scripts/eks-install-alb-controller.sh"
"$REPO_ROOT/scripts/eks-install-cloudwatch-observability.sh"

echo ""
kubectl get nodes -o wide
echo ""
echo "EKS deploy complete. Next: make eks-verify && make cdk-deploy-iam"
