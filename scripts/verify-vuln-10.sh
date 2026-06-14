#!/usr/bin/env bash
# T174 — vuln-10: weak CI/CD workflow + broad GitHub OIDC deploy role.
set -euo pipefail
source "$(dirname "$0")/vuln-evidence-common.sh"
source "$(dirname "$0")/cdk-outputs.sh"
vuln_evidence_init "10"
exec > >(tee "$EVIDENCE_FILE") 2>&1

DEPLOY_YML="${REPO_ROOT}/.github/workflows/deploy.yml"
WORKFLOW_COPY="${EVIDENCE_DIR}/vuln-10-deploy-workflow-${STAMP}.yaml"
ROLE_POLICY="${EVIDENCE_DIR}/vuln-10-github-role-policy-${STAMP}.json"

echo "=== T174 / vuln-10 — CI/CD + OIDC role ==="
[[ -f "$DEPLOY_YML" ]] || vuln_fail "missing ${DEPLOY_YML}"
cp "$DEPLOY_YML" "$WORKFLOW_COPY"
cat "$WORKFLOW_COPY"

grep -q 'write-all' "$WORKFLOW_COPY" || vuln_fail "deploy.yml missing permissions: write-all"
grep -q '@main' "$WORKFLOW_COPY" || vuln_fail "deploy.yml missing unpinned @main action"
echo "✓ deploy.yml has write-all + @main action"

echo ""
if export_value GITHUB_ROLE_ARN TaskvaultGithubOidc GithubDeployRoleArn 2>/dev/null; then
  ROLE_NAME="${GITHUB_ROLE_ARN##*/}"
  echo "GitHub deploy role: ${GITHUB_ROLE_ARN}"

  TRUST="$(aws iam get-role --role-name "$ROLE_NAME" --query 'Role.AssumeRolePolicyDocument' --output json)"
  echo "$TRUST" | tee "${EVIDENCE_DIR}/vuln-10-trust-${STAMP}.json"
  echo "$TRUST" | grep -q 'token.actions.githubusercontent.com:sub' || vuln_fail "missing OIDC trust"
  echo "$TRUST" | grep -q 'taskvault-demo:\*' && echo "✓ broad repo:* trust condition" \
    || echo "WARN: trust may use substituted githubOrg — inspect trust JSON"

  INLINE="$(aws iam list-role-policies --role-name "$ROLE_NAME" --query 'PolicyNames' --output json)"
  MANAGED="$(aws iam list-attached-role-policies --role-name "$ROLE_NAME" --output json)"
  python3 - "$ROLE_POLICY" "$INLINE" "$MANAGED" <<'PY'
import json, sys
from pathlib import Path
out, inline, managed = sys.argv[1:4]
Path(out).write_text(json.dumps({
  "inline_policy_names": json.loads(inline),
  "attached_policies": json.loads(managed),
}, indent=2) + "\n")
PY
  cat "$ROLE_POLICY"
  echo "$ROLE_POLICY" | grep -qi 'ECR\|eks\|s3' && echo "✓ over-broad deploy permissions present"
else
  echo "WARN: TaskvaultGithubOidc stack not deployed — using CDK source as offline evidence"
  CDK_SRC="${REPO_ROOT}/infra/cdk/lib/github-oidc-role-stack.ts"
  cp "$CDK_SRC" "${EVIDENCE_DIR}/vuln-10-github-oidc-source-${STAMP}.ts"
  cat "$CDK_SRC"
  grep -q 'taskvault-demo:\*' "$CDK_SRC" || vuln_fail "CDK source missing broad OIDC trust"
  grep -q 'AmazonEC2ContainerRegistryPowerUser' "$CDK_SRC" || vuln_fail "CDK source missing broad managed policy"
  echo '{"source":"cdk","file":"infra/cdk/lib/github-oidc-role-stack.ts"}' >"$ROLE_POLICY"
fi

python3 - "$EVIDENCE_JSON" "$WORKFLOW_COPY" "$ROLE_POLICY" <<'PY'
import json, sys
from pathlib import Path
Path(sys.argv[1]).write_text(json.dumps({
  "vuln_id": "vuln-10",
  "task": "T174",
  "deploy_workflow": sys.argv[2],
  "github_role_policy": sys.argv[3],
  "verified": True,
}, indent=2) + "\n")
PY

vuln_record_artifact "vuln-10" "$EVIDENCE_FILE"
echo "✓ T174 evidence: ${EVIDENCE_FILE}"
