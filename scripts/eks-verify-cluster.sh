#!/usr/bin/env bash
# T148 / T150 — Verify EKS nodes, add-ons, OIDC provider, ALB controller.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/cdk-outputs.sh
source "$REPO_ROOT/scripts/cdk-outputs.sh"

CLUSTER_NAME="${EKS_CLUSTER_NAME:-taskvault-eks}"
REGION="${AWS_REGION:-us-east-1}"
NAMESPACE_INGRESS="${INGRESS_NAMESPACE:-ingress-nginx}"
EVIDENCE_DIR="${EVIDENCE_DIR:-$REPO_ROOT/artifacts/sample}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ | tr '[:upper:]' '[:lower:]')"
EVIDENCE_FILE="${EVIDENCE_DIR}/eks-cluster-verify-${STAMP}.txt"

mkdir -p "$EVIDENCE_DIR"
exec > >(tee "$EVIDENCE_FILE") 2>&1

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

log() {
  echo ""
  echo "=== $* ==="
}

log "T148 — Nodes"
kubectl get nodes -o wide
not_ready="$(kubectl get nodes --no-headers 2>/dev/null | awk '$2 != "Ready" {c++} END {print c+0}')"
if [[ "$not_ready" -gt 0 ]]; then
  fail "${not_ready} node(s) not Ready"
fi
echo "✓ all nodes Ready"

log "T148 — EBS CSI add-on"
aws eks describe-addon \
  --cluster-name "$CLUSTER_NAME" \
  --addon-name aws-ebs-csi-driver \
  --region "$REGION" \
  --query 'addon.status' --output text

log "T148 — Node group"
aws eks describe-nodegroup \
  --cluster-name "$CLUSTER_NAME" \
  --nodegroup-name taskvault-ng \
  --region "$REGION" \
  --query 'nodegroup.{status:status,desired:scalingConfig.desiredSize}' \
  --output table

log "T148 — OIDC provider"
export_value OIDC_ISSUER TaskvaultEks ClusterOidcIssuer
ACCOUNT="$(account_id)"
OIDC_PROVIDERS="$(aws iam list-open-id-connect-providers --query 'OpenIDConnectProviderList[].Arn' --output text)"
echo "Cluster issuer: ${OIDC_ISSUER}"
echo "IAM OIDC providers: ${OIDC_PROVIDERS}"
if ! echo "$OIDC_PROVIDERS" | grep -q "$ACCOUNT"; then
  fail "no OIDC provider found in IAM for account ${ACCOUNT}"
fi
echo "✓ OIDC provider present"

log "T150 — ALB controller"
kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller -o wide
ALB_POD="$(kubectl get pods -n kube-system -l app.kubernetes.io/name=aws-load-balancer-controller -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
if [[ -z "$ALB_POD" ]]; then
  fail "aws-load-balancer-controller pod not found"
fi
kubectl wait -n kube-system --for=condition=ready "pod/${ALB_POD}" --timeout=120s
echo "--- recent controller logs ---"
kubectl logs -n kube-system "$ALB_POD" --tail=30
echo "✓ ALB controller pod ready"

log "T150 — Subnet discovery tags (T122)"
aws ec2 describe-subnets \
  --region "$REGION" \
  --filters "Name=tag:kubernetes.io/cluster/${CLUSTER_NAME},Values=shared" \
  --query 'Subnets[*].{SubnetId:SubnetId,AZ:AvailabilityZone,Public:MapPublicIpOnLaunch,ElbRole:Tags[?Key==`kubernetes.io/role/elb`].Value|[0],InternalElb:Tags[?Key==`kubernetes.io/role/internal-elb`].Value|[0]}' \
  --output table

echo ""
echo "Cluster verification passed. Evidence: ${EVIDENCE_FILE}"
