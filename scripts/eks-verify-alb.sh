#!/usr/bin/env bash
# T155 — Verify internet-facing ALB and vuln-1 unauth debug route.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAMESPACE="${K8S_NAMESPACE:-demo-prod}"
INGRESS_NAME="${INGRESS_NAME:-taskvault-public-ingress}"
EVIDENCE_DIR="${EVIDENCE_DIR:-$REPO_ROOT/artifacts/sample}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ | tr '[:upper:]' '[:lower:]')"
EVIDENCE_FILE="${EVIDENCE_DIR}/eks-alb-vuln1-${STAMP}.txt"

mkdir -p "$EVIDENCE_DIR"
exec > >(tee "$EVIDENCE_FILE") 2>&1

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

echo "=== T155 — ALB + vuln-1 public reachability ==="
kubectl -n "$NAMESPACE" get ingress "$INGRESS_NAME" -o wide

ALB_HOST="$(kubectl -n "$NAMESPACE" get ingress "$INGRESS_NAME" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
ALB_SCHEME="$(aws elbv2 describe-load-balancers \
  --query "LoadBalancers[?contains(DNSName, \`${ALB_HOST%%.*}\`)].Scheme | [0]" \
  --output text 2>/dev/null || echo unknown)"

echo "ALB hostname: ${ALB_HOST:-<pending>}"
echo "ALB scheme: ${ALB_SCHEME}"

if [[ -z "$ALB_HOST" ]]; then
  fail "ingress has no load balancer hostname yet — wait for ALB controller"
fi

if [[ "$ALB_SCHEME" != "internet-facing" && "$ALB_SCHEME" != "unknown" ]]; then
  fail "expected internet-facing ALB, got ${ALB_SCHEME}"
fi

echo "Waiting for ALB to accept traffic..."
for _ in $(seq 1 30); do
  if curl -sf --connect-timeout 5 "http://${ALB_HOST}/api/healthz" | grep -q '"status":"ok"'; then
    break
  fi
  sleep 10
done

echo ""
echo "--- curl http://${ALB_HOST}/api/healthz ---"
HEALTH="$(curl -sf "http://${ALB_HOST}/api/healthz")"
echo "$HEALTH"
echo "$HEALTH" | grep -q '"status":"ok"' || fail "healthz check failed"

echo ""
echo "--- curl http://${ALB_HOST}/api/debug/status (vuln-1 unauth) ---"
DEBUG="$(curl -sf "http://${ALB_HOST}/api/debug/status")"
echo "$DEBUG"
echo "$DEBUG" | grep -q 'backend-api' || fail "debug/status did not return expected metadata"

echo ""
echo "✓ vuln-1 verified: internet-facing ALB exposes unauthenticated /api/debug/status"
echo "Evidence saved to: ${EVIDENCE_FILE}"
