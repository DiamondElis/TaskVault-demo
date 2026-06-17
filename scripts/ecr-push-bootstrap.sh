#!/usr/bin/env bash
# T153 — Tag and push local images to ECR as :bootstrap.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# shellcheck source=scripts/lib/taskvault-aws.sh
source "$REPO_ROOT/scripts/lib/taskvault-aws.sh"
# shellcheck source=scripts/cdk-outputs.sh
source "$REPO_ROOT/scripts/cdk-outputs.sh"

TAG="${ECR_BOOTSTRAP_TAG:-bootstrap}"
ACCOUNT="$(account_id)"
REGISTRY="${ACCOUNT}.dkr.ecr.${AWS_REGION}.amazonaws.com"

export_value FRONTEND_REPO TaskvaultEcr FrontendRepoUri
export_value BACKEND_REPO TaskvaultEcr BackendRepoUri
export_value WORKER_REPO TaskvaultEcr WorkerRepoUri

if ! docker image inspect taskvault-backend:local >/dev/null 2>&1; then
  echo "Building local images for EKS (linux/amd64)..."
  make docker-build DOCKER_PLATFORM=linux/amd64
else
  # EKS nodes are amd64 — rebuild if local images may be ARM (Docker Desktop on Apple Silicon).
  echo "Rebuilding images for EKS (linux/amd64) before push..."
  make docker-build DOCKER_PLATFORM=linux/amd64
fi

echo "Logging in to ECR ${REGISTRY} (profile ${AWS_PROFILE})..."
taskvault_aws ecr get-login-password | docker login --username AWS --password-stdin "$REGISTRY"

push_image() {
  local local_name="$1"
  local ecr_uri="$2"
  local ecr_tag="$3"
  echo "Pushing ${local_name} -> ${ecr_uri}:${ecr_tag}"
  docker tag "${local_name}" "${ecr_uri}:${ecr_tag}"
  docker push "${ecr_uri}:${ecr_tag}"
}

push_image taskvault-frontend:local "$FRONTEND_REPO" "$TAG"
push_image taskvault-backend:local "$BACKEND_REPO" "$TAG"
push_image taskvault-worker:local "$WORKER_REPO" "$TAG"
push_image taskvault-backend-migrator:local "$BACKEND_REPO" "${TAG}-migrator"

echo ""
echo "Bootstrap images pushed:"
echo "  ${FRONTEND_REPO}:${TAG}"
echo "  ${BACKEND_REPO}:${TAG}"
echo "  ${WORKER_REPO}:${TAG}"
echo "  ${BACKEND_REPO}:${TAG}-migrator (db-migrator)"
