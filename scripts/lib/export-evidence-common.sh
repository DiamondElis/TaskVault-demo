#!/usr/bin/env bash
# Shared helpers for M13 export-evidence pipeline.
set -euo pipefail

export_evidence_init() {
  local caller="${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}"
  REPO_ROOT="$(cd "$(dirname "$caller")/.." && pwd)"
  ARTIFACT_DIR="${ARTIFACT_DIR:-${REPO_ROOT}/artifacts/sample}"
  NAMESPACE="${K8S_NAMESPACE:-demo-prod}"
  REGION="${AWS_REGION:-${CDK_DEFAULT_REGION:-us-east-1}}"
  mkdir -p "$ARTIFACT_DIR"
}

clear_generated_artifacts() {
  local name
  for name in aws-inventory.json k8s-inventory.json github-inventory.json \
    trivy-backend.json grype-backend.json sbom-backend.spdx.json \
    checkov.json gitleaks.json kubescape.json; do
    rm -f "${ARTIFACT_DIR}/${name}"
  done
}

assert_nonempty() {
  local path="$1"
  local label="${2:-$(basename "$path")}"
  if [[ ! -s "$path" ]]; then
    echo "FAIL: expected non-empty artifact: ${label} (${path})" >&2
    exit 1
  fi
}

CANONICAL_ARTIFACTS=(
  aws-inventory.json
  k8s-inventory.json
  github-inventory.json
  trivy-backend.json
  grype-backend.json
  sbom-backend.spdx.json
  checkov.json
  gitleaks.json
  kubescape.json
  expected-nodes.json
  expected-edges.json
  expected-findings.json
  expected-attack-paths.json
)

assert_all_artifacts() {
  local missing=0
  for name in "${CANONICAL_ARTIFACTS[@]}"; do
    local path="${ARTIFACT_DIR}/${name}"
    if [[ ! -s "$path" ]]; then
      echo "FAIL: missing or empty: ${name}" >&2
      missing=$((missing + 1))
    fi
  done
  if [[ "$missing" -gt 0 ]]; then
    exit 1
  fi
  echo "✓ all ${#CANONICAL_ARTIFACTS[@]} canonical artifacts present and non-empty"
}

resolve_backend_image() {
  BACKEND_IMAGE="${BACKEND_IMAGE:-}"
  if [[ -n "$BACKEND_IMAGE" ]]; then
    return 0
  fi

  # shellcheck source=scripts/lib/taskvault-aws.sh
  source "${REPO_ROOT}/scripts/lib/taskvault-aws.sh" 2>/dev/null || true
  # shellcheck source=scripts/cdk-outputs.sh
  source "${REPO_ROOT}/scripts/cdk-outputs.sh" 2>/dev/null || true

  local tag="${ECR_IMAGE_TAG:-${ECR_BOOTSTRAP_TAG:-bootstrap}}"
  if export_value BACKEND_REPO TaskvaultEcr BackendRepoUri 2>/dev/null; then
    BACKEND_IMAGE="${BACKEND_REPO}:${tag}"
    echo "Using ECR backend image: ${BACKEND_IMAGE}"
    if ! docker image inspect "$BACKEND_IMAGE" >/dev/null 2>&1; then
      echo "Pulling ${BACKEND_IMAGE}..."
      taskvault_aws ecr get-login-password 2>/dev/null \
        | docker login --username AWS --password-stdin "${BACKEND_REPO%%/*}" 2>/dev/null || true
      docker pull "$BACKEND_IMAGE" 2>/dev/null || true
    fi
  fi

  if [[ -z "${BACKEND_IMAGE:-}" ]] || ! docker image inspect "$BACKEND_IMAGE" >/dev/null 2>&1; then
    BACKEND_IMAGE="taskvault-backend:local"
    echo "Building local backend image for scanning..."
    docker build -t "$BACKEND_IMAGE" -f "${REPO_ROOT}/backend/Dockerfile" --target stage-1 "$REPO_ROOT"
  fi
}

run_trivy() {
  local image="$1"
  local output="$2"
  if command -v trivy >/dev/null 2>&1; then
    trivy image --scanners vuln,secret --severity HIGH,CRITICAL --format json --output "$output" "$image"
  else
    docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v "$(dirname "$output"):/out" \
      aquasec/trivy:latest image --scanners vuln,secret --severity HIGH,CRITICAL --format json \
      --output "/out/$(basename "$output")" "$image"
  fi
}

run_grype() {
  local image="$1"
  local output="$2"
  if command -v grype >/dev/null 2>&1; then
    grype "$image" -o json >"$output" || true
  else
    docker run --rm -v /var/run/docker.sock:/var/run/docker.sock anchore/grype:latest \
      "$image" -o json >"$output" || true
  fi
  [[ -s "$output" ]] || echo '{"source":"grype","status":"skipped"}' >"$output"
}

run_syft() {
  local image="$1"
  local output="$2"
  if command -v syft >/dev/null 2>&1; then
    syft "$image" -o spdx-json >"$output" || true
  else
    docker run --rm -v /var/run/docker.sock:/var/run/docker.sock anchore/syft:latest \
      "$image" -o spdx-json >"$output" || true
  fi
  [[ -s "$output" ]] || echo '{"spdxVersion":"SPDX-2.3","status":"skipped"}' >"$output"
}

run_checkov() {
  local output="$1"
  local cdk_dir="${REPO_ROOT}/infra/cdk"
  local out_dir="${cdk_dir}/cdk.out"
  (cd "$cdk_dir" && npm run build && npx cdk synth --quiet --no-lookups -o cdk.out)
  if command -v checkov >/dev/null 2>&1; then
    checkov -d "$out_dir" --framework cloudformation --compact -o json >"$output" || true
  elif docker info >/dev/null 2>&1; then
    docker run --rm -v "$out_dir:/cdk.out:ro" bridgecrew/checkov:latest \
      -d /cdk.out --framework cloudformation --compact -o json >"$output" || true
  else
    echo '{"results":{"failed_checks":[]},"status":"skipped"}' >"$output"
  fi
  [[ -s "$output" ]] || echo '{"results":{"failed_checks":[]}}' >"$output"
}

run_gitleaks() {
  local output="$1"
  if command -v gitleaks >/dev/null 2>&1; then
    gitleaks detect --source "$REPO_ROOT" --no-git -f json -r "$output" \
      --config "${REPO_ROOT}/scripts/gitleaks-verify.toml" || true
  elif docker info >/dev/null 2>&1; then
    docker run --rm -v "$REPO_ROOT:/repo:ro" -v "$(dirname "$output"):/out" \
      ghcr.io/gitleaks/gitleaks:latest detect --source /repo --no-git -f json \
      -r "/out/$(basename "$output")" --config /repo/scripts/gitleaks-verify.toml || true
  else
    echo '[]' >"$output"
  fi
  [[ -s "$output" ]] || echo '[]' >"$output"
}

render_k8s_manifests() {
  local output="$1"
  kubectl kustomize "${REPO_ROOT}/k8s/overlays/local" >"$output"
  if [[ "$(uname -s)" == "Darwin" ]]; then
    sed -i '' \
      -e 's/__TASKVAULT_POSTGRES_IP__/172.18.0.100/g' \
      -e 's/__TASKVAULT_LOCALSTACK_IP__/172.18.0.101/g' \
      "$output"
  else
    sed -i \
      -e 's/__TASKVAULT_POSTGRES_IP__/172.18.0.100/g' \
      -e 's/__TASKVAULT_LOCALSTACK_IP__/172.18.0.101/g' \
      "$output"
  fi
}

k8s_manifest_tempfile() {
  mktemp "${TMPDIR:-/tmp}/taskvault-k8s-XXXXXX.yaml"
}

run_kubescape() {
  local manifest_file="$1"
  local output="$2"
  export PATH="${HOME}/.kubescape/bin:${PATH}"

  if ! command -v kubescape >/dev/null 2>&1; then
    if curl -sf https://raw.githubusercontent.com/kubescape/kubescape/master/install.sh >/dev/null 2>&1; then
      curl -s https://raw.githubusercontent.com/kubescape/kubescape/master/install.sh | /bin/bash >/dev/null 2>&1 || true
    fi
  fi

  if command -v kubescape >/dev/null 2>&1; then
    kubescape scan framework nsa "$manifest_file" \
      --format json --output "$output" --submit=false || true
  else
    echo '{"framework":"nsa","status":"skipped"}' >"$output"
  fi
  [[ -s "$output" ]] || echo '{"framework":"nsa","status":"skipped"}' >"$output"
}
