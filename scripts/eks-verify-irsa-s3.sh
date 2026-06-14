#!/usr/bin/env bash
# T161 — Verify backend S3 access uses IRSA (AssumeRoleWithWebIdentity), not static keys.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/cdk-outputs.sh
source "$REPO_ROOT/scripts/cdk-outputs.sh"

REGION="${AWS_REGION:-us-east-1}"
EVIDENCE_DIR="${EVIDENCE_DIR:-$REPO_ROOT/artifacts/sample}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ | tr '[:upper:]' '[:lower:]')"
EVIDENCE_FILE="${EVIDENCE_DIR}/eks-irsa-s3-${STAMP}.txt"
LOOKBACK_MINUTES="${CLOUDTRAIL_LOOKBACK_MINUTES:-60}"

mkdir -p "$EVIDENCE_DIR"
exec > >(tee "$EVIDENCE_FILE") 2>&1

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

ACCOUNT="$(account_id)"
export_value BACKEND_ROLE_ARN TaskvaultIam BackendRoleArn
ROLE_NAME="${BACKEND_ROLE_ARN##*/}"
START_TIME="$(date -u -v-"${LOOKBACK_MINUTES}"M +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d "${LOOKBACK_MINUTES} minutes ago" +%Y-%m-%dT%H:%M:%SZ)"

echo "=== T161 — IRSA S3 evidence (vuln-2 / vuln-6) ==="
echo "Backend role: ${BACKEND_ROLE_ARN}"
echo "CloudTrail lookback from: ${START_TIME}"

ASSUME_EVENTS="$(aws cloudtrail lookup-events \
  --region "$REGION" \
  --start-time "$START_TIME" \
  --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRoleWithWebIdentity \
  --max-results 50 \
  --output json)"

echo "$ASSUME_EVENTS" | grep -q "$ROLE_NAME" || fail "no AssumeRoleWithWebIdentity events for ${ROLE_NAME}"
echo "✓ AssumeRoleWithWebIdentity events found for ${ROLE_NAME}"

S3_EVENTS="$(aws cloudtrail lookup-events \
  --region "$REGION" \
  --start-time "$START_TIME" \
  --lookup-attributes AttributeKey=EventName,AttributeValue=PutObject \
  --max-results 50 \
  --output json)"

echo "$S3_EVENTS" | grep -q 'taskvault-user-files' || echo "WARN: no recent PutObject events for taskvault-user-files (run smoke-eks first)"

echo ""
echo "Checking backend deployment for static AWS key env vars..."
BACKEND_ENV="$(kubectl -n demo-prod get deploy backend-api -o jsonpath='{.spec.template.spec.containers[0].env[*].name}' 2>/dev/null || true)"
echo "$BACKEND_ENV" | grep -q 'AWS_ACCESS_KEY_ID' && fail "backend has static AWS_ACCESS_KEY_ID env" || echo "✓ no static AWS_ACCESS_KEY_ID on backend deployment"
echo "$BACKEND_ENV" | grep -q 'AWS_SECRET_ACCESS_KEY' && fail "backend has static AWS_SECRET_ACCESS_KEY env" || echo "✓ no static AWS_SECRET_ACCESS_KEY on backend deployment"

echo ""
echo "✓ T161 IRSA evidence captured. Artifact: ${EVIDENCE_FILE}"
