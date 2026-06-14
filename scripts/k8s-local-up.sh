#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

CLUSTER_NAME="${KIND_CLUSTER_NAME:-taskvault}"
NAMESPACE="${K8S_NAMESPACE:-demo-prod}"
OVERLAY_SRC="${K8S_OVERLAY_SRC:-k8s/overlays/local}"
OVERLAY_BUILD=""

cleanup() {
  if [[ -n "$OVERLAY_BUILD" && -d "$OVERLAY_BUILD" ]]; then
    rm -rf "$OVERLAY_BUILD"
  fi
}
trap cleanup EXIT

if ! kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
  echo "Kind cluster '${CLUSTER_NAME}' not found — run './scripts/kind-up.sh' first." >&2
  exit 1
fi

kind export kubeconfig --name "$CLUSTER_NAME" >/dev/null

if ! docker image inspect taskvault-backend:local >/dev/null 2>&1; then
  echo "Building local images..."
  make docker-build
fi

if ! docker exec taskvault-postgres pg_isready -U demo -d taskvault >/dev/null 2>&1; then
  echo "Postgres not ready — run './scripts/kind-up.sh' to start infrastructure." >&2
  exit 1
fi

chmod +x scripts/kind-connect-infra.sh
read -r POSTGRES_KIND_IP LOCALSTACK_KIND_IP <<<"$(./scripts/kind-connect-infra.sh)"

OVERLAY_BUILD="$(mktemp -d)"
mkdir -p "$OVERLAY_BUILD/base" "$OVERLAY_BUILD/overlays/local"
cp -r k8s/base/. "$OVERLAY_BUILD/base/"
cp -r "$OVERLAY_SRC/." "$OVERLAY_BUILD/overlays/local/"
for patch in secrets-patch.yaml config-patch.yaml; do
  if [[ "$(uname -s)" == "Darwin" ]]; then
    sed -i '' \
      -e "s/__TASKVAULT_POSTGRES_IP__/${POSTGRES_KIND_IP}/g" \
      -e "s/__TASKVAULT_LOCALSTACK_IP__/${LOCALSTACK_KIND_IP}/g" \
      "$OVERLAY_BUILD/overlays/local/${patch}"
  else
    sed -i \
      -e "s/__TASKVAULT_POSTGRES_IP__/${POSTGRES_KIND_IP}/g" \
      -e "s/__TASKVAULT_LOCALSTACK_IP__/${LOCALSTACK_KIND_IP}/g" \
      "$OVERLAY_BUILD/overlays/local/${patch}"
  fi
done
OVERLAY_APPLY="$OVERLAY_BUILD/overlays/local"

./scripts/kind-load-images.sh

echo "Applying overlay (Postgres ${POSTGRES_KIND_IP}, LocalStack ${LOCALSTACK_KIND_IP} on kind network)..."
kubectl -n "$NAMESPACE" delete job db-migrator report-job --ignore-not-found
kubectl apply -k "$OVERLAY_APPLY"

echo "Running db-migrator job..."
kubectl -n "$NAMESPACE" wait --for=condition=complete job/db-migrator --timeout=180s

echo "Waiting for deployments..."
kubectl -n "$NAMESPACE" rollout status deployment/frontend --timeout=180s
kubectl -n "$NAMESPACE" rollout status deployment/backend-api --timeout=180s
kubectl -n "$NAMESPACE" rollout status deployment/worker --timeout=180s

echo ""
kubectl -n "$NAMESPACE" get deploy,pod,svc,ingress
echo ""
echo "TaskVault workloads applied to kind. Run './scripts/k8s-local-validate.sh' to verify."
