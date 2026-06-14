#!/usr/bin/env bash
# Shared helper: render k8s/overlays/eks with CDK output placeholders substituted.
set -euo pipefail

eks_render_overlay() {
  local repo_root
  repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  # shellcheck source=scripts/cdk-outputs.sh
  source "$repo_root/scripts/cdk-outputs.sh"

  local overlay_build region account registry tag migrator_image
  overlay_build="$(mktemp -d)"
  region="${AWS_REGION:-us-east-1}"
  account="$(account_id)"
  registry="${account}.dkr.ecr.${region}.amazonaws.com"
  tag="${ECR_IMAGE_TAG:-${ECR_BOOTSTRAP_TAG:-bootstrap}}"

  export_value BACKEND_ROLE_ARN TaskvaultIam BackendRoleArn
  export_value WORKER_ROLE_ARN TaskvaultIam WorkerRoleArn
  export_value SQS_QUEUE_URL TaskvaultStorage JobsQueueUrl
  export_value BACKEND_REPO TaskvaultEcr BackendRepoUri
  migrator_image="${BACKEND_REPO}:${tag}-migrator"

  mkdir -p "$overlay_build/base" "$overlay_build/overlays/eks"
  cp -r "$repo_root/k8s/base/." "$overlay_build/base/"
  cp -r "$repo_root/k8s/overlays/eks/." "$overlay_build/overlays/eks/"

  for f in "$overlay_build/overlays/eks"/*.yaml; do
    if [[ "$(uname -s)" == "Darwin" ]]; then
      sed -i '' \
        -e "s|__TASKVAULT_ECR_REGISTRY__|${registry}|g" \
        -e "s|__TASKVAULT_BACKEND_ROLE_ARN__|${BACKEND_ROLE_ARN}|g" \
        -e "s|__TASKVAULT_WORKER_ROLE_ARN__|${WORKER_ROLE_ARN}|g" \
        -e "s|__TASKVAULT_SQS_QUEUE_URL__|${SQS_QUEUE_URL}|g" \
        -e "s|__TASKVAULT_IMAGE_TAG__|${tag}|g" \
        -e "s|__TASKVAULT_BACKEND_MIGRATOR_IMAGE__|${migrator_image}|g" \
        "$f"
    else
      sed -i \
        -e "s|__TASKVAULT_ECR_REGISTRY__|${registry}|g" \
        -e "s|__TASKVAULT_BACKEND_ROLE_ARN__|${BACKEND_ROLE_ARN}|g" \
        -e "s|__TASKVAULT_WORKER_ROLE_ARN__|${WORKER_ROLE_ARN}|g" \
        -e "s|__TASKVAULT_SQS_QUEUE_URL__|${SQS_QUEUE_URL}|g" \
        -e "s|__TASKVAULT_IMAGE_TAG__|${tag}|g" \
        -e "s|__TASKVAULT_BACKEND_MIGRATOR_IMAGE__|${migrator_image}|g" \
        "$f"
    fi
  done

  printf '%s' "$overlay_build"
}
