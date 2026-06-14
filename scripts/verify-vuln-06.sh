#!/usr/bin/env bash
# T170 — vuln-6: IRSA bridge backend-sa → backend role → S3 + Secrets Manager.
set -euo pipefail
source "$(dirname "$0")/vuln-evidence-common.sh"
source "$(dirname "$0")/cdk-outputs.sh"
vuln_evidence_init "06"
exec > >(tee "$EVIDENCE_FILE") 2>&1

export_value BACKEND_ROLE_ARN TaskvaultIam BackendRoleArn
ROLE_NAME="${BACKEND_ROLE_ARN##*/}"
LOOKBACK_MINUTES="${CLOUDTRAIL_LOOKBACK_MINUTES:-120}"
START_TIME="$(date -u -v-"${LOOKBACK_MINUTES}"M +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "${LOOKBACK_MINUTES} minutes ago" +%Y-%m-%dT%H:%M:%SZ)"

echo "=== T170 / vuln-6 — IRSA pivot chain ==="

echo "--- backend-sa IRSA annotation ---"
IRSA="$(kubectl -n "$NAMESPACE" get sa backend-sa -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}')"
echo "backend-sa role-arn: ${IRSA}"
echo "$IRSA" | grep -q 'taskvault-backend-role' || vuln_fail "backend-sa not bound to taskvault-backend-role"

echo ""
echo "--- IAM policy: secretsmanager:GetSecretValue on taskvault/demo/* ---"
POLICY="$(aws iam get-role-policy --role-name "$ROLE_NAME" --policy-name "$(aws iam list-role-policies --role-name "$ROLE_NAME" --query 'PolicyNames[0]' --output text)" --output json)"
echo "$POLICY" | tee "${EVIDENCE_DIR}/vuln-06-policy-${STAMP}.json"
echo "$POLICY" | grep -q 'secretsmanager:GetSecretValue' || vuln_fail "missing Secrets Manager permission"
echo "$POLICY" | grep -q 'taskvault/demo' || vuln_fail "missing taskvault/demo secret scope"

echo ""
echo "--- CloudTrail: AssumeRoleWithWebIdentity for backend role ---"
ASSUME="$(aws cloudtrail lookup-events --region "$REGION" --start-time "$START_TIME" \
  --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity \
  --max-results 50 --output json)"
echo "$ASSUME" | tee "${EVIDENCE_DIR}/vuln-06-assume-${STAMP}.json" | grep -q "$ROLE_NAME" \
  || echo "WARN: no recent AssumeRoleWithWebIdentity — run smoke-eks first"

echo ""
echo "--- CloudTrail: GetSecretValue (runtime SM read) ---"
SM_EVENTS="$(aws cloudtrail lookup-events --region "$REGION" --start-time "$START_TIME" \
  --lookup-attributes AttributeKey=EventName,AttributeValue=GetSecretValue \
  --max-results 50 --output json)"
echo "$SM_EVENTS" | tee "${EVIDENCE_DIR}/vuln-06-getsecret-${STAMP}.json"
echo "$SM_EVENTS" | grep -q 'taskvault/demo' && echo "✓ GetSecretValue events for taskvault/demo secrets" \
  || echo "WARN: no GetSecretValue events in lookback window — ensure workloads restarted with USE_SECRETS_MANAGER=true"

echo ""
echo "--- CloudTrail: S3 data plane (IRSA-backed writes) ---"
S3_EVENTS="$(aws cloudtrail lookup-events --region "$REGION" --start-time "$START_TIME" \
  --lookup-attributes AttributeKey=EventName,AttributeValue=PutObject \
  --max-results 50 --output json)"
echo "$S3_EVENTS" | tee "${EVIDENCE_DIR}/vuln-06-s3-${STAMP}.json" | grep -q 'taskvault' \
  && echo "✓ S3 PutObject events present" || echo "WARN: no recent S3 PutObject events"

python3 - "$EVIDENCE_JSON" <<'PY'
import json, sys
from pathlib import Path
Path(sys.argv[1]).write_text(json.dumps({
  "vuln_id": "vuln-6",
  "task": "T170",
  "chain": "backend-sa -> taskvault-backend-role -> S3 + secretsmanager:GetSecretValue",
  "verified": True,
}, indent=2) + "\n")
PY

vuln_record_artifact "vuln-6" "$EVIDENCE_FILE"
echo "✓ T170 evidence: ${EVIDENCE_FILE}"
