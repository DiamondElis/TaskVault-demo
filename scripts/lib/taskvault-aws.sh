#!/usr/bin/env bash
# Shared AWS defaults for TaskVault deploy/EKS scripts.
# Override with AWS_PROFILE / AWS_REGION in the environment.
TASKVAULT_AWS_PROFILE="${TASKVAULT_AWS_PROFILE:-taskvault-deploy}"
export AWS_PROFILE="${AWS_PROFILE:-$TASKVAULT_AWS_PROFILE}"
export AWS_REGION="${AWS_REGION:-${CDK_DEFAULT_REGION:-us-east-1}}"

taskvault_aws() {
  aws --profile "$AWS_PROFILE" "$@"
}

taskvault_eks_update_kubeconfig() {
  local cluster_name="${1:?cluster name required}"
  taskvault_aws eks update-kubeconfig --name "$cluster_name" --region "$AWS_REGION"
}
