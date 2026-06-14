#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

CLUSTER_NAME="${KIND_CLUSTER_NAME:-taskvault}"
KIND_CONFIG="${KIND_CONFIG:-scripts/kind-config.yaml}"
INGRESS_MANIFEST="${INGRESS_MANIFEST:-https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.11.3/deploy/static/provider/kind/deploy.yaml}"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_cmd kind
require_cmd kubectl
require_cmd docker

echo "TaskVault kind bootstrap (cluster: ${CLUSTER_NAME})"
echo ""
echo "Local vs EKS (summary — see docs/kind-local.md):"
echo "  - kind uses ingress-nginx, not AWS ALB (vuln-1 route shape is preserved)."
echo "  - IRSA role-arn annotations are dummy placeholders; no real web identity."
echo "  - S3/SQS/Postgres reach docker-compose via kind Docker network (static IPs)."
echo "  - No CloudTrail, Inspector, or real IAM session credentials in-cluster."
echo ""

if ! kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
  echo "Creating kind cluster..."
  kind create cluster --name "$CLUSTER_NAME" --config "$KIND_CONFIG"
else
  echo "Kind cluster '${CLUSTER_NAME}' already exists."
  kind export kubeconfig --name "$CLUSTER_NAME" >/dev/null
fi

echo "Starting docker-compose infrastructure (Postgres + LocalStack only)..."
docker compose -f docker-compose.local.yml up -d postgres localstack
echo "Waiting for Postgres..."
until docker exec taskvault-postgres pg_isready -U demo -d taskvault >/dev/null 2>&1; do sleep 1; done
echo "Waiting for LocalStack..."
until curl -sf http://localhost:4566/_localstack/health | grep -qE '"s3": "(available|running)"'; do sleep 2; done
until docker exec taskvault-localstack awslocal s3 ls s3://taskvault-user-files >/dev/null 2>&1 \
  && docker exec taskvault-localstack awslocal sqs get-queue-url --queue-name taskvault-jobs >/dev/null 2>&1; do
  sleep 2
done

chmod +x scripts/kind-connect-infra.sh
INFRA_IPS="$(./scripts/kind-connect-infra.sh)"
echo "Attached Postgres + LocalStack to kind network: ${INFRA_IPS}"

echo "Installing ingress-nginx for kind..."
kubectl apply -f "$INGRESS_MANIFEST"
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=180s

echo ""
echo "Kind cluster ready."
echo "  kubeconfig: kind export kubeconfig --name ${CLUSTER_NAME}"
echo "  ingress:    http://localhost:8088 (mapped from node port 80)"
echo "Next: make kind-load-images && make k8s-local-up"
