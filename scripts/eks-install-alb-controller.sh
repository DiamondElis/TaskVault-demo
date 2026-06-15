#!/usr/bin/env bash
# Install AWS Load Balancer Controller via Helm (outside CloudFormation).
# Idempotent and retriable — avoids CFN rollback when Helm is interrupted.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/taskvault-aws.sh
source "$REPO_ROOT/scripts/lib/taskvault-aws.sh"

NAMESPACE="kube-system"
RELEASE="aws-load-balancer-controller"
CHART_VERSION="${ALB_CONTROLLER_CHART_VERSION:-1.8.2}"
CONTROLLER_TAG="${ALB_CONTROLLER_TAG:-v2.8.2}"
REPLICA_COUNT="${ALB_CONTROLLER_REPLICAS:-1}"
IMAGE_REPO="${ALB_CONTROLLER_IMAGE_REPO:-public.ecr.aws/eks/aws-load-balancer-controller}"

CLUSTER_NAME="${EKS_CLUSTER_NAME:-taskvault-eks}"
VPC_ID="${TASKVAULT_VPC_ID:-}"
if [[ -z "$VPC_ID" ]]; then
  VPC_ID="$(taskvault_aws cloudformation describe-stacks \
    --stack-name TaskvaultNetwork \
    --query 'Stacks[0].Outputs[?OutputKey==`VpcId`].OutputValue' \
    --output text)"
fi

echo "Configuring kubeconfig for ${CLUSTER_NAME}..."
taskvault_eks_update_kubeconfig "$CLUSTER_NAME" >/dev/null

if ! kubectl get serviceaccount aws-load-balancer-controller -n "$NAMESPACE" >/dev/null 2>&1; then
  echo "ERROR: IRSA service account aws-load-balancer-controller not found in ${NAMESPACE}."
  echo "  Deploy TaskvaultEks CDK stack first (creates SA + IAM role, no Helm in CFN)."
  exit 1
fi

if ! command -v helm >/dev/null 2>&1; then
  echo "ERROR: helm required. Install: https://helm.sh/docs/intro/install/"
  exit 1
fi

helm repo add eks https://aws.github.io/eks-charts >/dev/null 2>&1 || true
helm repo update eks >/dev/null

if helm status "$RELEASE" -n "$NAMESPACE" >/dev/null 2>&1; then
  helm_status="$(helm status "$RELEASE" -n "$NAMESPACE" -o json | python3 -c "import json,sys; print(json.load(sys.stdin)['info']['status'])" 2>/dev/null || echo unknown)"
  echo "Existing Helm release status: ${helm_status}"
  if [[ "$helm_status" == "pending-install" || "$helm_status" == "pending-upgrade" || "$helm_status" == "pending-rollback" ]]; then
    echo "Rolling back stuck Helm release..."
    helm rollback "$RELEASE" -n "$NAMESPACE" 2>/dev/null || helm uninstall "$RELEASE" -n "$NAMESPACE" || true
    sleep 5
  fi
fi

echo "  replicas: ${REPLICA_COUNT}  image: ${IMAGE_REPO}:${CONTROLLER_TAG}"
echo "Installing ${RELEASE} chart ${CHART_VERSION} (controller ${CONTROLLER_TAG})..."
for attempt in 1 2 3; do
  if helm upgrade --install "$RELEASE" eks/aws-load-balancer-controller \
    --namespace "$NAMESPACE" \
    --version "$CHART_VERSION" \
    --wait \
    --timeout 15m \
    --set clusterName="$CLUSTER_NAME" \
    --set region="$AWS_REGION" \
    --set vpcId="$VPC_ID" \
    --set replicaCount="$REPLICA_COUNT" \
    --set serviceAccount.create=false \
    --set serviceAccount.name=aws-load-balancer-controller \
    --set image.repository="$IMAGE_REPO" \
    --set image.tag="$CONTROLLER_TAG"; then
    echo "✓ ALB controller installed"
    kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=aws-load-balancer-controller -o wide
    exit 0
  fi
  echo "WARN: helm attempt ${attempt} failed — retrying in 30s..."
  sleep 30
done

echo "ERROR: ALB controller Helm install failed after 3 attempts"
exit 1
