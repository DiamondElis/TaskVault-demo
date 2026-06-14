#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"
export PATH="${HOME}/.kubescape/bin:${PATH}"

CLUSTER_NAME="${KIND_CLUSTER_NAME:-taskvault}"
NAMESPACE="${K8S_NAMESPACE:-demo-prod}"
EVIDENCE_DIR="${EVIDENCE_DIR:-artifacts/sample}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ | tr '[:upper:]' '[:lower:]')"
MANIFEST_BUILD="$(mktemp)"
RENDERED="${EVIDENCE_DIR}/k8s-local-rendered-${STAMP}.yaml"
OUTPUT_JSON="${EVIDENCE_DIR}/kubescape-kind-${STAMP}.json"
OUTPUT_TXT="${EVIDENCE_DIR}/kubescape-kind-${STAMP}.txt"

mkdir -p "$EVIDENCE_DIR"

kubectl kustomize k8s/overlays/local >"$MANIFEST_BUILD"
# Substitute kind-network placeholders so rendered YAML is valid for offline scans.
sed -i.bak \
  -e 's/__TASKVAULT_POSTGRES_IP__/172.18.0.100/g' \
  -e 's/__TASKVAULT_LOCALSTACK_IP__/172.18.0.101/g' \
  "$MANIFEST_BUILD"
rm -f "${MANIFEST_BUILD}.bak"
cp "$MANIFEST_BUILD" "$RENDERED"

run_kubescape() {
  local -a args=(scan framework nsa --format json --output "$OUTPUT_JSON" --submit=false)
  if [[ "${KUBESCAPE_SCAN_CLUSTER:-1}" == "1" ]] && kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
    kind export kubeconfig --name "$CLUSTER_NAME" >/dev/null
    echo "Scanning live kind cluster (namespace ${NAMESPACE})..."
    kubescape scan framework nsa --include-namespaces "$NAMESPACE" \
      --format json --output "$OUTPUT_JSON" --submit=false
  else
    echo "Scanning rendered manifests..."
    kubescape "${args[@]}" --file "$MANIFEST_BUILD"
  fi
}

if command -v kubescape >/dev/null 2>&1; then
  run_kubescape
elif docker info >/dev/null 2>&1; then
  echo "Running kubescape via docker..."
  kind export kubeconfig --name "$CLUSTER_NAME" >/dev/null 2>&1 || true
  KUBECONFIG_PATH="${KUBECONFIG:-$HOME/.kube/config}"
  docker run --rm \
    -v "$REPO_ROOT:/work" \
    -v "$KUBECONFIG_PATH:/root/.kube/config:ro" \
    quay.io/kubescape/kubescape:latest \
    scan framework nsa --include-namespaces "$NAMESPACE" \
      --format json --output "/work/${OUTPUT_JSON}" --submit=false
else
  echo "kubescape not found and Docker unavailable." >&2
  exit 1
fi

if command -v jq >/dev/null 2>&1; then
  jq -r '
    .summaryDetails.controls[]?
    | select(.statusInfo.failedResources != null and .statusInfo.failedResources > 0)
    | "\(.controlID // .name): \(.statusInfo.failedResources) failed"
  ' "$OUTPUT_JSON" | tee "$OUTPUT_TXT" || true

  echo ""
  echo "Checking for expected weakness signals..."
  for signal in privileged root hostPath networkPolicy limits; do
    if grep -qi "$signal" "$OUTPUT_JSON"; then
      echo "  • kubescape output mentions: ${signal}"
    fi
  done
else
  cp "$OUTPUT_JSON" "${OUTPUT_JSON%.json}.copy"
  echo "jq not installed — raw JSON at ${OUTPUT_JSON}"
fi

echo ""
echo "Kubescape artifacts:"
echo "  ${OUTPUT_JSON}"
echo "  ${RENDERED}"

rm -f "$MANIFEST_BUILD"
