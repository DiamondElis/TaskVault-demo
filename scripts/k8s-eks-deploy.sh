#!/usr/bin/env bash
# T151–T154 — Build eks overlay from CDK outputs and apply to EKS.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# shellcheck source=scripts/cdk-outputs.sh
source "$REPO_ROOT/scripts/cdk-outputs.sh"

CLUSTER_NAME="${EKS_CLUSTER_NAME:-taskvault-eks}"
REGION="${AWS_REGION:-us-east-1}"
NAMESPACE="${K8S_NAMESPACE:-demo-prod}"
OVERLAY_SRC="k8s/overlays/eks"
OVERLAY_BUILD=""
TAG="${ECR_IMAGE_TAG:-${ECR_BOOTSTRAP_TAG:-bootstrap}}"

cleanup() {
  if [[ -n "$OVERLAY_BUILD" && -d "$OVERLAY_BUILD" ]]; then
    rm -rf "$OVERLAY_BUILD"
  fi
}
trap cleanup EXIT

aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION" >/dev/null

ACCOUNT="$(account_id)"
REGISTRY="${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com"

export_value BACKEND_ROLE_ARN TaskvaultIam BackendRoleArn
export_value WORKER_ROLE_ARN TaskvaultIam WorkerRoleArn
export_value SQS_QUEUE_URL TaskvaultStorage JobsQueueUrl
export_value BACKEND_REPO TaskvaultEcr BackendRepoUri

MIGRATOR_IMAGE="${BACKEND_REPO}:${TAG}-migrator"

OVERLAY_BUILD="$(mktemp -d)"
mkdir -p "$OVERLAY_BUILD/base" "$OVERLAY_BUILD/overlays/eks"
cp -r k8s/base/. "$OVERLAY_BUILD/base/"
cp -r "$OVERLAY_SRC/." "$OVERLAY_BUILD/overlays/eks/"

replace_placeholders() {
  local file="$1"
  if [[ "$(uname -s)" == "Darwin" ]]; then
    sed -i '' \
      -e "s|__TASKVAULT_ECR_REGISTRY__|${REGISTRY}|g" \
      -e "s|__TASKVAULT_BACKEND_ROLE_ARN__|${BACKEND_ROLE_ARN}|g" \
      -e "s|__TASKVAULT_WORKER_ROLE_ARN__|${WORKER_ROLE_ARN}|g" \
      -e "s|__TASKVAULT_SQS_QUEUE_URL__|${SQS_QUEUE_URL}|g" \
      -e "s|__TASKVAULT_IMAGE_TAG__|${TAG}|g" \
      -e "s|__TASKVAULT_BACKEND_MIGRATOR_IMAGE__|${MIGRATOR_IMAGE}|g" \
      "$file"
  else
    sed -i \
      -e "s|__TASKVAULT_ECR_REGISTRY__|${REGISTRY}|g" \
      -e "s|__TASKVAULT_BACKEND_ROLE_ARN__|${BACKEND_ROLE_ARN}|g" \
      -e "s|__TASKVAULT_WORKER_ROLE_ARN__|${WORKER_ROLE_ARN}|g" \
      -e "s|__TASKVAULT_SQS_QUEUE_URL__|${SQS_QUEUE_URL}|g" \
      -e "s|__TASKVAULT_IMAGE_TAG__|${TAG}|g" \
      -e "s|__TASKVAULT_BACKEND_MIGRATOR_IMAGE__|${MIGRATOR_IMAGE}|g" \
      "$file"
  fi
}

for f in \
  "$OVERLAY_BUILD/overlays/eks/kustomization.yaml" \
  "$OVERLAY_BUILD/overlays/eks/serviceaccount-irsa-patch.yaml" \
  "$OVERLAY_BUILD/overlays/eks/config-patch.yaml" \
  "$OVERLAY_BUILD/overlays/eks/jobs-patch.yaml"; do
  replace_placeholders "$f"
done

OVERLAY_APPLY="$OVERLAY_BUILD/overlays/eks"

echo "Applying EKS overlay (registry ${REGISTRY}, tag ${TAG})..."
kubectl -n "$NAMESPACE" delete job db-migrator report-job --ignore-not-found
kubectl apply -k "$OVERLAY_APPLY"

echo "Running db-migrator job..."
kubectl -n "$NAMESPACE" wait --for=condition=complete job/db-migrator --timeout=300s

echo "Waiting for deployments..."
kubectl -n "$NAMESPACE" rollout status deployment/frontend --timeout=300s
kubectl -n "$NAMESPACE" rollout status deployment/backend-api --timeout=300s
kubectl -n "$NAMESPACE" rollout status deployment/worker --timeout=300s

echo ""
echo "ServiceAccount IRSA annotations:"
kubectl -n "$NAMESPACE" get sa backend-sa worker-sa -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.annotations.eks\.amazonaws\.com/role-arn}{"\n"}{end}'

echo ""
kubectl -n "$NAMESPACE" get deploy,pod,svc,ingress
echo ""
echo "EKS workloads applied. Run: make eks-verify-alb && make eks-verify-logs"
