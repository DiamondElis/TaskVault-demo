#!/usr/bin/env bash
# T161 — Verify backend S3 access uses IRSA (AssumeRoleWithWebIdentity), not static keys.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/taskvault-aws.sh
source "$REPO_ROOT/scripts/lib/taskvault-aws.sh"
# shellcheck source=scripts/cdk-outputs.sh
source "$REPO_ROOT/scripts/cdk-outputs.sh"

REGION="${AWS_REGION:-us-east-1}"
NAMESPACE="${K8S_NAMESPACE:-demo-prod}"
EVIDENCE_DIR="${EVIDENCE_DIR:-$REPO_ROOT/artifacts/sample}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ | tr '[:upper:]' '[:lower:]')"
EVIDENCE_FILE="${EVIDENCE_DIR}/eks-irsa-s3-${STAMP}.txt"
LOOKBACK_MINUTES="${CLOUDTRAIL_LOOKBACK_MINUTES:-1440}"
REFRESH_IRSA="${REFRESH_IRSA:-true}"

mkdir -p "$EVIDENCE_DIR"
exec > >(tee "$EVIDENCE_FILE") 2>&1

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

start_time() {
  date -u -v-"${LOOKBACK_MINUTES}"M +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || date -u -d "${LOOKBACK_MINUTES} minutes ago" +%Y-%m-%dT%H:%M:%SZ
}

backend_assume_events() {
  local start="$1"
  taskvault_aws cloudtrail lookup-events \
    --region "$REGION" \
    --start-time "$start" \
    --lookup-attributes "AttributeKey=ResourceName,AttributeValue=${BACKEND_ROLE_ARN}" \
    --max-results 50 \
    --output json
}

count_assume_events() {
  python3 -c "import json,sys; print(len(json.load(sys.stdin).get('Events', [])))" <<<"$1"
}

ACCOUNT="$(account_id)"
export_value BACKEND_ROLE_ARN TaskvaultIam BackendRoleArn
ROLE_NAME="${BACKEND_ROLE_ARN##*/}"
START_TIME="$(start_time)"

echo "=== T161 — IRSA S3 evidence (vuln-2 / vuln-6) ==="
echo "AWS profile: ${AWS_PROFILE}  region: ${REGION}"
echo "Backend role: ${BACKEND_ROLE_ARN}"
echo "CloudTrail lookback from: ${START_TIME} (${LOOKBACK_MINUTES}m)"

echo ""
echo "--- backend-sa IRSA annotation ---"
IRSA="$(kubectl -n "$NAMESPACE" get sa backend-sa -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}' 2>/dev/null || true)"
echo "backend-sa role-arn: ${IRSA:-<missing>}"
[[ "$IRSA" == "$BACKEND_ROLE_ARN" ]] || fail "backend-sa IRSA annotation does not match ${BACKEND_ROLE_ARN}"

echo ""
echo "Checking backend deployment for static AWS key env vars..."
BACKEND_ENV="$(kubectl -n "$NAMESPACE" get deploy backend-api -o jsonpath='{.spec.template.spec.containers[0].env[*].name}' 2>/dev/null || true)"
echo "$BACKEND_ENV" | grep -q 'AWS_ACCESS_KEY_ID' && fail "backend has static AWS_ACCESS_KEY_ID env" || echo "✓ no static AWS_ACCESS_KEY_ID on backend deployment"
echo "$BACKEND_ENV" | grep -q 'AWS_SECRET_ACCESS_KEY' && fail "backend has static AWS_SECRET_ACCESS_KEY env" || echo "✓ no static AWS_SECRET_ACCESS_KEY on backend deployment"

echo ""
echo "--- CloudTrail: AssumeRoleWithWebIdentity for ${ROLE_NAME} ---"
ASSUME_EVENTS="$(backend_assume_events "$START_TIME")"
ASSUME_COUNT="$(count_assume_events "$ASSUME_EVENTS")"
echo "Events in lookback window: ${ASSUME_COUNT}"

if [[ "$ASSUME_COUNT" -eq 0 && "$REFRESH_IRSA" == "true" ]]; then
  echo "No recent IRSA assume events — restarting backend-api to refresh web identity token..."
  kubectl -n "$NAMESPACE" rollout restart deploy/backend-api
  kubectl -n "$NAMESPACE" rollout status deploy/backend-api --timeout=180s
  echo "Waiting for CloudTrail delivery..."
  for _ in $(seq 1 12); do
    sleep 10
    ASSUME_EVENTS="$(backend_assume_events "$(date -u -v-5M +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%SZ)")"
    ASSUME_COUNT="$(count_assume_events "$ASSUME_EVENTS")"
    echo "  post-restart events (5m window): ${ASSUME_COUNT}"
    if [[ "$ASSUME_COUNT" -gt 0 ]]; then
      break
    fi
  done
fi

[[ "$ASSUME_COUNT" -gt 0 ]] || fail "no AssumeRoleWithWebIdentity events for ${BACKEND_ROLE_ARN} — check CloudTrail trail and IRSA wiring"
echo "✓ AssumeRoleWithWebIdentity events found for ${ROLE_NAME}"

S3_EVENTS="$(taskvault_aws cloudtrail lookup-events \
  --region "$REGION" \
  --start-time "$START_TIME" \
  --lookup-attributes AttributeKey=EventName,AttributeValue=PutObject \
  --max-results 50 \
  --output json)"

echo "$S3_EVENTS" | grep -q 'taskvault-user-files' && echo "✓ recent PutObject events for taskvault-user-files" \
  || echo "WARN: no recent PutObject events for taskvault-user-files (run smoke-eks for S3 data-plane evidence)"

echo ""
echo "✓ T161 IRSA evidence captured. Artifact: ${EVIDENCE_FILE}"
