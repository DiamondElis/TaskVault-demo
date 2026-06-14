#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

OVERLAY="${1:-local}"
BUILD_DIR="$(mktemp -d)"
trap 'rm -rf "$BUILD_DIR"' EXIT

render_overlay() {
  if [[ "$OVERLAY" == "eks" ]]; then
    local tmp
    tmp="$(mktemp -d)"
    mkdir -p "$tmp/base" "$tmp/overlays/eks"
    cp -r k8s/base/. "$tmp/base/"
    cp -r k8s/overlays/eks/. "$tmp/overlays/eks/"
    for f in "$tmp/overlays/eks"/*.yaml; do
      if [[ "$(uname -s)" == "Darwin" ]]; then
        sed -i '' \
          -e 's|__TASKVAULT_ECR_REGISTRY__|111111111111.dkr.ecr.us-east-1.amazonaws.com|g' \
          -e 's|__TASKVAULT_BACKEND_ROLE_ARN__|arn:aws:iam::111111111111:role/taskvault-backend-role|g' \
          -e 's|__TASKVAULT_WORKER_ROLE_ARN__|arn:aws:iam::111111111111:role/taskvault-worker-role|g' \
          -e 's|__TASKVAULT_SQS_QUEUE_URL__|https://sqs.us-east-1.amazonaws.com/111111111111/taskvault-jobs|g' \
          -e 's|__TASKVAULT_IMAGE_TAG__|bootstrap|g' \
          -e 's|__TASKVAULT_BACKEND_MIGRATOR_IMAGE__|111111111111.dkr.ecr.us-east-1.amazonaws.com/taskvault-backend:bootstrap-migrator|g' \
          "$f"
      else
        sed -i \
          -e 's|__TASKVAULT_ECR_REGISTRY__|111111111111.dkr.ecr.us-east-1.amazonaws.com|g' \
          -e 's|__TASKVAULT_BACKEND_ROLE_ARN__|arn:aws:iam::111111111111:role/taskvault-backend-role|g' \
          -e 's|__TASKVAULT_WORKER_ROLE_ARN__|arn:aws:iam::111111111111:role/taskvault-worker-role|g' \
          -e 's|__TASKVAULT_SQS_QUEUE_URL__|https://sqs.us-east-1.amazonaws.com/111111111111/taskvault-jobs|g' \
          -e 's|__TASKVAULT_IMAGE_TAG__|bootstrap|g' \
          -e 's|__TASKVAULT_BACKEND_MIGRATOR_IMAGE__|111111111111.dkr.ecr.us-east-1.amazonaws.com/taskvault-backend:bootstrap-migrator|g' \
          "$f"
      fi
    done
    kubectl kustomize "$tmp/overlays/eks"
    rm -rf "$tmp"
  else
    kubectl kustomize "k8s/overlays/${OVERLAY}"
  fi
}

echo "Rendering k8s/overlays/${OVERLAY}..."
render_overlay >"${BUILD_DIR}/manifests.yaml"

if command -v kubeconform >/dev/null 2>&1; then
  echo "Linting with kubeconform..."
  kubeconform -summary -ignore-missing-schemas "${BUILD_DIR}/manifests.yaml"
elif docker info >/dev/null 2>&1; then
  echo "Linting with kubeconform (docker)..."
  docker run --rm -v "${BUILD_DIR}:/work" ghcr.io/yannh/kubeconform:latest \
    -summary -ignore-missing-schemas /work/manifests.yaml
else
  echo "kubeconform not found and Docker unavailable — rendered manifest only:"
  wc -l "${BUILD_DIR}/manifests.yaml"
  exit 1
fi

echo "k8s lint passed for overlay: ${OVERLAY}"
