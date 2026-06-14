#!/usr/bin/env bash
# T166 — vuln-2: backend role broad S3 access (s3:* on taskvault-*).
set -euo pipefail
source "$(dirname "$0")/vuln-evidence-common.sh"
source "$(dirname "$0")/cdk-outputs.sh"
vuln_evidence_init "02"
exec > >(tee "$EVIDENCE_FILE") 2>&1

export_value BACKEND_ROLE_ARN TaskvaultIam BackendRoleArn
ROLE_NAME="${BACKEND_ROLE_ARN##*/}"
POLICY_JSON="${EVIDENCE_DIR}/vuln-02-policy-${STAMP}.json"

echo "=== T166 / vuln-2 — backend IAM S3 policy ==="
echo "Role: ${BACKEND_ROLE_ARN}"

aws iam list-role-policies --role-name "$ROLE_NAME" --output json | tee "${EVIDENCE_DIR}/vuln-02-inline-policy-names-${STAMP}.json"
INLINE_NAME="$(aws iam list-role-policies --role-name "$ROLE_NAME" --query 'PolicyNames[0]' --output text)"
aws iam get-role-policy --role-name "$ROLE_NAME" --policy-name "$INLINE_NAME" --output json >"$POLICY_JSON"
cat "$POLICY_JSON"

grep -q 's3:\*' "$POLICY_JSON" || vuln_fail "policy missing s3:*"
grep -q 'taskvault-\*' "$POLICY_JSON" || vuln_fail "policy missing taskvault-* resource scope"

echo ""
echo "--- iam simulate-principal-policy (s3:PutObject on taskvault-user-files) ---"
ACCOUNT="$(account_id)"
SIMULATE="$(aws iam simulate-principal-policy \
  --policy-source-arn "$BACKEND_ROLE_ARN" \
  --action-names s3:PutObject s3:GetObject s3:DeleteObject s3:ListBucket \
  --resource-arns \
    "arn:aws:s3:::taskvault-user-files" \
    "arn:aws:s3:::taskvault-user-files/uploads/sensitive/payroll-export-demo.csv" \
  --output json)"
echo "$SIMULATE" | tee "${EVIDENCE_DIR}/vuln-02-simulate-${STAMP}.json"
echo "$SIMULATE" | grep -q '"EvalDecision": "allowed"' || vuln_fail "simulate-principal-policy did not allow S3 actions"

python3 - "$EVIDENCE_JSON" "$POLICY_JSON" "${EVIDENCE_DIR}/vuln-02-simulate-${STAMP}.json" <<'PY'
import json, sys
from pathlib import Path
out, policy, simulate = sys.argv[1:4]
Path(out).write_text(json.dumps({
  "vuln_id": "vuln-2",
  "task": "T166",
  "policy_json": policy,
  "simulate_json": simulate,
  "verified": True,
}, indent=2) + "\n")
PY

vuln_record_artifact "vuln-2" "$EVIDENCE_FILE"
echo "✓ T166 evidence: ${EVIDENCE_FILE}"
