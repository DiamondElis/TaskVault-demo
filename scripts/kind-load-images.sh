#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

CLUSTER_NAME="${KIND_CLUSTER_NAME:-taskvault}"
IMAGE_TAG="${IMAGE_TAG:-local}"

require_image() {
  if ! docker image inspect "$1" >/dev/null 2>&1; then
    echo "Image $1 not found — run 'make docker-build' first." >&2
    exit 1
  fi
}

if ! kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
  echo "Kind cluster '${CLUSTER_NAME}' not found — run './scripts/kind-up.sh' first." >&2
  exit 1
fi

for image in taskvault-frontend taskvault-backend taskvault-backend-migrator taskvault-worker; do
  require_image "${image}:${IMAGE_TAG}"
done

echo "Loading local images into kind cluster '${CLUSTER_NAME}'..."
kind load docker-image "taskvault-frontend:${IMAGE_TAG}" --name "$CLUSTER_NAME"
kind load docker-image "taskvault-backend:${IMAGE_TAG}" --name "$CLUSTER_NAME"
kind load docker-image "taskvault-backend-migrator:${IMAGE_TAG}" --name "$CLUSTER_NAME"
kind load docker-image "taskvault-worker:${IMAGE_TAG}" --name "$CLUSTER_NAME"
echo "Images loaded."
