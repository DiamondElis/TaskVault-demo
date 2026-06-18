#!/usr/bin/env bash
# Shared AWS defaults for TaskVault deploy/EKS scripts.
# Override with AWS_PROFILE / AWS_REGION in the environment.
#
# Locally we default to the taskvault-deploy CLI profile. In CI (GitHub Actions
# OIDC) credentials are injected via the environment and no named profile
# exists, so we must NOT force --profile there.
TASKVAULT_AWS_PROFILE="${TASKVAULT_AWS_PROFILE:-taskvault-deploy}"

if [[ -n "${AWS_PROFILE:-}" ]]; then
  export AWS_PROFILE
elif [[ "${GITHUB_ACTIONS:-}" == "true" || -n "${AWS_ACCESS_KEY_ID:-}" || -n "${AWS_WEB_IDENTITY_TOKEN_FILE:-}" ]]; then
  unset AWS_PROFILE
else
  export AWS_PROFILE="$TASKVAULT_AWS_PROFILE"
fi
export AWS_REGION="${AWS_REGION:-${CDK_DEFAULT_REGION:-us-east-1}}"

taskvault_aws() {
  if [[ -n "${AWS_PROFILE:-}" ]]; then
    aws --profile "$AWS_PROFILE" "$@"
  else
    aws "$@"
  fi
}

taskvault_eks_update_kubeconfig() {
  local cluster_name="${1:?cluster name required}"
  taskvault_aws eks update-kubeconfig --name "$cluster_name" --region "$AWS_REGION"
}
