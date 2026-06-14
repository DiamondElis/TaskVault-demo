#!/usr/bin/env bash
# Attach docker-compose Postgres + LocalStack to the kind Docker network with stable IPs
# so in-cluster pods can reach host-side infra without a registry or host port forwarding.
set -euo pipefail

CLUSTER_NAME="${KIND_CLUSTER_NAME:-taskvault}"
NETWORK="${KIND_DOCKER_NETWORK:-kind}"
POSTGRES_CONTAINER="${POSTGRES_CONTAINER:-taskvault-postgres}"
LOCALSTACK_CONTAINER="${LOCALSTACK_CONTAINER:-taskvault-localstack}"
POSTGRES_KIND_IP="${POSTGRES_KIND_IP:-172.18.0.100}"
LOCALSTACK_KIND_IP="${LOCALSTACK_KIND_IP:-172.18.0.101}"

connect_with_ip() {
  local container="$1"
  local ip="$2"
  shift 2
  local aliases=("$@")

  if ! docker inspect "$container" >/dev/null 2>&1; then
    echo "Container '${container}' not found — start docker-compose infra first." >&2
    exit 1
  fi

  if docker inspect "$container" --format '{{json .NetworkSettings.Networks}}' | grep -q "\"${NETWORK}\""; then
    current_ip="$(docker inspect "$container" --format "{{range \$k, \$v := .NetworkSettings.Networks}}{{if eq \$k \"${NETWORK}\"}}{{\$v.IPAddress}}{{end}}{{end}}")"
    if [[ "$current_ip" == "$ip" ]]; then
      return 0
    fi
    docker network disconnect "$NETWORK" "$container" >/dev/null 2>&1 || true
  fi

  local alias_args=()
  for alias in "${aliases[@]}"; do
    alias_args+=(--alias "$alias")
  done
  docker network connect --ip "$ip" "${alias_args[@]}" "$NETWORK" "$container"
}

connect_with_ip "$POSTGRES_CONTAINER" "$POSTGRES_KIND_IP" postgres taskvault-postgres
connect_with_ip "$LOCALSTACK_CONTAINER" "$LOCALSTACK_KIND_IP" localstack taskvault-localstack

echo "${POSTGRES_KIND_IP} ${LOCALSTACK_KIND_IP}"
