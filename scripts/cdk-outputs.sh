#!/usr/bin/env bash
# Read CloudFormation outputs for TaskVault CDK stacks.
set -euo pipefail

REGION="${AWS_REGION:-${CDK_DEFAULT_REGION:-us-east-1}}"

output() {
  local stack="$1"
  local key="$2"
  aws cloudformation describe-stacks \
    --region "$REGION" \
    --stack-name "$stack" \
    --query "Stacks[0].Outputs[?OutputKey=='${key}'].OutputValue | [0]" \
    --output text 2>/dev/null || true
}

export_value() {
  local name="$1"
  local stack="$2"
  local key="$3"
  local value
  value="$(output "$stack" "$key")"
  if [[ -z "$value" || "$value" == "None" ]]; then
    echo "Missing output ${key} from stack ${stack}" >&2
    return 1
  fi
  printf -v "$name" '%s' "$value"
  export "$name"
}

account_id() {
  aws sts get-caller-identity --query Account --output text
}
