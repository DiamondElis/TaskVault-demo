#!/usr/bin/env bash
# CI deploy entrypoint — apply overlays/eks with commit-SHA image tags (T184).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export ECR_IMAGE_TAG="${ECR_IMAGE_TAG:-${GITHUB_SHA:-}}"
export EKS_CLUSTER_NAME="${EKS_CLUSTER_NAME:-taskvault-eks}"
export AWS_REGION="${AWS_REGION:-us-east-1}"

if [[ -z "$ECR_IMAGE_TAG" ]]; then
  echo "ECR_IMAGE_TAG or GITHUB_SHA is required" >&2
  exit 1
fi

echo "Deploying TaskVault to EKS with image tag: ${ECR_IMAGE_TAG}"
exec "$REPO_ROOT/scripts/k8s-eks-deploy.sh"
