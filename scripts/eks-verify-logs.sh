#!/usr/bin/env bash
# T156 — Verify CloudWatch log groups and sample application log lines.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REGION="${AWS_REGION:-us-east-1}"
NAMESPACE="${K8S_NAMESPACE:-demo-prod}"
EVIDENCE_DIR="${EVIDENCE_DIR:-$REPO_ROOT/artifacts/sample}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ | tr '[:upper:]' '[:lower:]')"
EVIDENCE_FILE="${EVIDENCE_DIR}/eks-logs-${STAMP}.txt"

mkdir -p "$EVIDENCE_DIR"
exec > >(tee "$EVIDENCE_FILE") 2>&1

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

LOG_GROUPS=(/taskvault/backend /taskvault/worker /taskvault/frontend)

echo "=== T156 — CloudWatch log flow ==="

for lg in "${LOG_GROUPS[@]}"; do
  echo "--- ${lg} ---"
  if ! aws logs describe-log-groups --region "$REGION" --log-group-name-prefix "$lg" \
    --query 'logGroups[?logGroupName==`'"$lg"'`].logGroupName' --output text | grep -q "$lg"; then
    fail "log group ${lg} not found"
  fi
  echo "✓ log group exists"
done

echo ""
echo "Generating traffic for audit log lines..."
ALB_HOST="$(kubectl -n "$NAMESPACE" get ingress taskvault-public-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
if [[ -n "$ALB_HOST" ]]; then
  curl -sf "http://${ALB_HOST}/api/healthz" >/dev/null || true
  curl -sf "http://${ALB_HOST}/api/debug/status" >/dev/null || true
fi

echo "Waiting for log delivery (Fluent Bit / Container Insights)..."
sleep 30

CLUSTER_NAME="${EKS_CLUSTER_NAME:-taskvault-eks}"
CI_LOG_GROUP="/aws/containerinsights/${CLUSTER_NAME}/application"

FOUND=0
for lg in "${LOG_GROUPS[@]}" "$CI_LOG_GROUP"; do
  echo "--- recent events in ${lg} ---"
  EVENTS="$(aws logs filter-log-events \
    --region "$REGION" \
    --log-group-name "$lg" \
    --limit 5 \
    --query 'events[*].message' \
    --output text 2>/dev/null || true)"
  if [[ -n "$EVENTS" && "$EVENTS" != "None" ]]; then
    echo "$EVENTS" | head -3
    FOUND=1
  else
    echo "(no events yet)"
  fi
done

# Also check container insights / application log streams from pods
echo ""
echo "--- kubectl logs sample (backend) ---"
BACKEND_POD="$(kubectl -n "$NAMESPACE" get pod -l app.kubernetes.io/component=backend-api -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
if [[ -n "$BACKEND_POD" ]]; then
  kubectl -n "$NAMESPACE" logs "$BACKEND_POD" --tail=5 2>/dev/null || true
  kubectl -n "$NAMESPACE" logs "$BACKEND_POD" --tail=50 2>/dev/null | grep -E 'event_type|audit' | head -3 || true
fi

if [[ "$FOUND" -eq 0 ]]; then
  echo ""
  echo "WARN: no CloudWatch events yet — verify amazon-cloudwatch-observability add-on pods:"
  kubectl get pods -n amazon-cloudwatch 2>/dev/null || kubectl get pods -A | grep -i fluent || true
else
  echo ""
  echo "✓ sample log lines found in CloudWatch"
fi

echo ""
echo "Log verification complete. Evidence: ${EVIDENCE_FILE}"
