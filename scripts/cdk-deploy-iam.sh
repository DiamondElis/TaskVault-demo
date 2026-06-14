#!/usr/bin/env bash
# T149 — Deploy IRSA workload roles + GitHub OIDC after cluster OIDC provider exists.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT/infra/cdk"

npm install
npm run build

STACKS=(TaskvaultIam TaskvaultGithubOidc)

echo "Deploying IAM stacks: ${STACKS[*]}"
npx cdk deploy "${STACKS[@]}" --require-approval never

# shellcheck source=scripts/cdk-outputs.sh
source "$REPO_ROOT/scripts/cdk-outputs.sh"

export_value BACKEND_ROLE_ARN TaskvaultIam BackendRoleArn
export_value WORKER_ROLE_ARN TaskvaultIam WorkerRoleArn
export_value GITHUB_DEPLOY_ROLE_ARN TaskvaultGithubOidc GithubDeployRoleArn

EVIDENCE_DIR="${EVIDENCE_DIR:-$REPO_ROOT/artifacts/sample}"
mkdir -p "$EVIDENCE_DIR"
STAMP="$(date -u +%Y%m%dT%H%M%SZ | tr '[:upper:]' '[:lower:]')"
ARN_FILE="${EVIDENCE_DIR}/eks-iam-roles-${STAMP}.txt"

cat >"$ARN_FILE" <<EOF
taskvault-backend-role=${BACKEND_ROLE_ARN}
taskvault-worker-role=${WORKER_ROLE_ARN}
taskvault-github-deploy-role=${GITHUB_DEPLOY_ROLE_ARN}
EOF

echo ""
echo "IAM role ARNs:"
cat "$ARN_FILE"
echo ""
echo "Saved to ${ARN_FILE}"
echo "Next: make ecr-push-bootstrap && make k8s-deploy"
