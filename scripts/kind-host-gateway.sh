#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="${KIND_CLUSTER_NAME:-taskvault}"
NODE="${CLUSTER_NAME}-control-plane"

if docker inspect "$NODE" >/dev/null 2>&1; then
  docker inspect "$NODE" --format '{{range .NetworkSettings.Networks}}{{.Gateway}}{{end}}'
else
  echo "host.docker.internal"
fi
