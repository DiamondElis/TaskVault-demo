#!/usr/bin/env bash
# Guard EKS CDK deploy against concurrent / failed CloudFormation states.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/taskvault-aws.sh
source "$REPO_ROOT/scripts/lib/taskvault-aws.sh"

STACK_NAME="${EKS_CFN_STACK:-TaskvaultEks}"

status() {
  taskvault_aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --query 'Stacks[0].StackStatus' \
    --output text 2>/dev/null || echo "NOT_FOUND"
}

CURRENT="$(status)"
echo "TaskvaultEks CloudFormation status: ${CURRENT}"

case "$CURRENT" in
  NOT_FOUND)
    echo "No existing stack — safe to deploy."
    ;;
  CREATE_COMPLETE|UPDATE_COMPLETE)
    echo "Stack already exists — CDK will update in place."
    ;;
  CREATE_IN_PROGRESS|UPDATE_IN_PROGRESS|UPDATE_COMPLETE_CLEANUP_IN_PROGRESS)
    echo "ERROR: ${STACK_NAME} is ${CURRENT}. Wait for it to finish before deploying."
    exit 1
    ;;
  ROLLBACK_COMPLETE|CREATE_FAILED|UPDATE_ROLLBACK_COMPLETE|UPDATE_ROLLBACK_FAILED)
    echo "ERROR: ${STACK_NAME} is ${CURRENT}. Delete the stack or fix drift before redeploying."
    echo "  See docs/eks-deploy.md — Recover from ROLLBACK_COMPLETE"
    exit 1
    ;;
  *)
    echo "WARN: unexpected status ${CURRENT} — proceeding"
    ;;
esac

if taskvault_aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --query 'Stacks[0].StackStatus' \
  --output text 2>/dev/null | grep -q IN_PROGRESS; then
  echo "ERROR: another CloudFormation operation is in progress on ${STACK_NAME}"
  exit 1
fi
