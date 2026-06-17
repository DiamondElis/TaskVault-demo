#!/usr/bin/env bash
# T164 — Verify report-cronjob triggers a Job and writes to taskvault-reports.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/cdk-outputs.sh
source "$REPO_ROOT/scripts/cdk-outputs.sh"

NAMESPACE="${K8S_NAMESPACE:-demo-prod}"
REGION="${AWS_REGION:-us-east-1}"
POLL_SECONDS="${CRONJOB_POLL_SECONDS:-180}"
EVIDENCE_DIR="${EVIDENCE_DIR:-$REPO_ROOT/artifacts/sample}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ | tr '[:upper:]' '[:lower:]')"
EVIDENCE_FILE="${EVIDENCE_DIR}/eks-report-cronjob-${STAMP}.txt"

mkdir -p "$EVIDENCE_DIR"
exec > >(tee "$EVIDENCE_FILE") 2>&1

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

echo "=== T164 — report-cronjob ==="
kubectl -n "$NAMESPACE" get cronjob report-cronjob -o wide

SUSPENDED="$(kubectl -n "$NAMESPACE" get cronjob report-cronjob -o jsonpath='{.spec.suspend}' 2>/dev/null || echo true)"
if [[ "$SUSPENDED" == "true" ]]; then
  fail "report-cronjob is suspended — expected active on EKS overlay"
fi

JOB_NAME="report-cronjob-manual-${STAMP}"
echo "Creating manual Job from cronjob template: ${JOB_NAME}"
kubectl -n "$NAMESPACE" create job "$JOB_NAME" --from=cronjob/report-cronjob

echo "Waiting for Job completion (timeout ${POLL_SECONDS}s)..."
kubectl -n "$NAMESPACE" wait --for=condition=complete "job/${JOB_NAME}" --timeout="${POLL_SECONDS}s"

echo ""
echo "--- cronjob Job logs ---"
kubectl -n "$NAMESPACE" logs "job/${JOB_NAME}"

export_value REPORTS_BUCKET TaskvaultStorage ReportsBucketName
echo ""
echo "Checking taskvault-reports for admin report objects..."
OBJECTS="$(aws s3api list-objects-v2 \
  --bucket "$REPORTS_BUCKET" \
  --prefix reports/admin/ \
  --query 'Contents[].Key' \
  --output text 2>/dev/null || true)"

if [[ -z "$OBJECTS" || "$OBJECTS" == "None" ]]; then
  echo "No reports/admin/ objects yet — waiting for worker to finish admin_report job..."
  DEADLINE=$((SECONDS + POLL_SECONDS))
  while (( SECONDS < DEADLINE )); do
    OBJECTS="$(aws s3api list-objects-v2 \
      --bucket "$REPORTS_BUCKET" \
      --prefix reports/admin/ \
      --query 'Contents[].Key' \
      --output text 2>/dev/null || true)"
    if [[ -n "$OBJECTS" && "$OBJECTS" != "None" ]]; then
      break
    fi
    sleep 5
  done
fi

[[ -n "$OBJECTS" && "$OBJECTS" != "None" ]] || fail "no report objects under s3://${REPORTS_BUCKET}/reports/admin/"
echo "✓ report objects present:"
echo "$OBJECTS" | tr '\t' '\n' | head -5

echo ""
echo "✓ T164 report-cronjob verified. Evidence: ${EVIDENCE_FILE}"
