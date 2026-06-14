#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="${KIND_CLUSTER_NAME:-taskvault}"

if kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
  echo "Deleting kind cluster '${CLUSTER_NAME}'..."
  kind delete cluster --name "$CLUSTER_NAME"
else
  echo "Kind cluster '${CLUSTER_NAME}' not found."
fi
