#!/usr/bin/env bash
# Create taskvault-deploy IAM user + local AWS CLI profile for CDK/EKS deploy.
#
# Requires credentials that can manage IAM (AdministratorAccess or equivalent).
# cnapp-local-dev is read-scoped and cannot run this — use root/admin in the
# AWS Console (IAM) or CloudShell first, then run:
#
#   ADMIN_AWS_PROFILE=<admin-profile> ./scripts/aws-create-deploy-user.sh
#
# Or paste admin keys once:
#   AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=... ./scripts/aws-create-deploy-user.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEPLOY_USER="${TASKVAULT_DEPLOY_USER:-taskvault-deploy}"
DEPLOY_PROFILE="${TASKVAULT_DEPLOY_PROFILE:-taskvault-deploy}"
AWS_REGION="${AWS_REGION:-us-east-1}"
ADMIN_PROFILE="${ADMIN_AWS_PROFILE:-}"

aws_admin() {
  if [[ -n "$ADMIN_PROFILE" ]]; then
    AWS_PROFILE="$ADMIN_PROFILE" aws "$@"
  else
    aws "$@"
  fi
}

require_iam_admin() {
  if ! aws_admin iam:GetUser --user-name "$DEPLOY_USER" >/dev/null 2>&1; then
    : # user may not exist yet — check a generic IAM action instead
  fi
  if ! aws_admin iam:ListUsers --max-items 1 >/dev/null 2>&1; then
    echo "ERROR: Current credentials cannot manage IAM."
    echo "  Log in as an account admin (Console → IAM, or CloudShell) and retry with:"
    echo "    ADMIN_AWS_PROFILE=<admin-profile> $0"
    exit 1
  fi
}

ensure_user() {
  if aws_admin iam:GetUser --user-name "$DEPLOY_USER" >/dev/null 2>&1; then
    echo "IAM user exists: ${DEPLOY_USER}"
  else
    echo "Creating IAM user: ${DEPLOY_USER}"
    aws_admin iam:CreateUser \
      --user-name "$DEPLOY_USER" \
      --tags Key=Project,Value=TaskVault Key=Purpose,Value=cdk-deploy
  fi
}

attach_admin_policy() {
  # PowerUserAccess is NOT enough for CDK (IAM roles, OIDC provider, IRSA).
  local policy_arn="arn:aws:iam::aws:policy/AdministratorAccess"
  if aws_admin iam:ListAttachedUserPolicies --user-name "$DEPLOY_USER" \
    --query "AttachedPolicies[?PolicyArn=='${policy_arn}'].PolicyArn" --output text | grep -q AdministratorAccess; then
    echo "Policy already attached: AdministratorAccess"
  else
    echo "Attaching AdministratorAccess to ${DEPLOY_USER} (demo sandbox account only)"
    aws_admin iam:AttachUserPolicy \
      --user-name "$DEPLOY_USER" \
      --policy-arn "$policy_arn"
  fi
}

create_access_key() {
  local keys_json
  keys_json="$(aws_admin iam:ListAccessKeys --user-name "$DEPLOY_USER" --output json)"
  local existing_count
  existing_count="$(echo "$keys_json" | python3 -c "import json,sys; print(len(json.load(sys.stdin).get('AccessKeyMetadata',[])))")"

  if [[ "$existing_count" -ge 2 ]]; then
    echo "ERROR: ${DEPLOY_USER} already has 2 access keys. Delete one in IAM Console, then re-run."
    exit 1
  fi

  if [[ "$existing_count" -ge 1 && "${ROTATE_DEPLOY_KEY:-}" != "true" ]]; then
    echo "Access key already exists for ${DEPLOY_USER}."
    echo "  Set ROTATE_DEPLOY_KEY=true to create a new key (deactivate old keys in IAM afterward)."
    return 0
  fi

  echo "Creating access key for ${DEPLOY_USER}"
  aws_admin iam:CreateAccessKey --user-name "$DEPLOY_USER" --output json > /tmp/taskvault-deploy-key.json
  ACCESS_KEY_ID="$(python3 -c "import json; print(json.load(open('/tmp/taskvault-deploy-key.json'))['AccessKey']['AccessKeyId'])")"
  SECRET_ACCESS_KEY="$(python3 -c "import json; print(json.load(open('/tmp/taskvault-deploy-key.json'))['AccessKey']['SecretAccessKey'])")"
  rm -f /tmp/taskvault-deploy-key.json

  mkdir -p "$HOME/.aws"
  if ! grep -q "^\[${DEPLOY_PROFILE}\]" "$HOME/.aws/credentials" 2>/dev/null; then
    cat >> "$HOME/.aws/credentials" <<EOF

[${DEPLOY_PROFILE}]
aws_access_key_id = ${ACCESS_KEY_ID}
aws_secret_access_key = ${SECRET_ACCESS_KEY}
EOF
  else
    aws configure set aws_access_key_id "$ACCESS_KEY_ID" --profile "$DEPLOY_PROFILE"
    aws configure set aws_secret_access_key "$SECRET_ACCESS_KEY" --profile "$DEPLOY_PROFILE"
  fi

  aws configure set region "$AWS_REGION" --profile "$DEPLOY_PROFILE"
  aws configure set output json --profile "$DEPLOY_PROFILE"

  echo "Wrote AWS CLI profile: ${DEPLOY_PROFILE}"
}

print_next_steps() {
  local account
  account="$(AWS_PROFILE="$DEPLOY_PROFILE" aws sts get-caller-identity --query Account --output text 2>/dev/null || true)"
  cat <<EOF

✓ Deploy profile ready.

Verify:
  export AWS_PROFILE=${DEPLOY_PROFILE}
  aws sts get-caller-identity

CDK bootstrap + deploy:
  export CDK_DEFAULT_ACCOUNT=${account:-<account-id>}
  export CDK_DEFAULT_REGION=${AWS_REGION}
  cd infra/cdk && npx cdk bootstrap
  cd ${REPO_ROOT} && make cdk-deploy

GitHub Actions (after OIDC stack deploy):
  Repository variable AWS_OIDC_ROLE_ARN=arn:aws:iam::${account:-<account-id>}:role/taskvault-github-deploy-role

Keep ${DEPLOY_PROFILE} for infra deploy only. Continue using cnapp-local-dev for day-to-day read/scanner work.
EOF
}

main() {
  echo "TaskVault deploy user setup (account admin required)"
  require_iam_admin
  ensure_user
  attach_admin_policy
  create_access_key
  print_next_steps
}

main "$@"
