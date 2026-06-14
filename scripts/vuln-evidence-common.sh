#!/usr/bin/env bash
# Shared helpers for M11 vulnerability verification scripts.
set -euo pipefail

vuln_evidence_init() {
  local vuln_id="$1"
  REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[1]}")/.." && pwd)"
  EVIDENCE_DIR="${EVIDENCE_DIR:-$REPO_ROOT/artifacts/sample}"
  STAMP="$(date -u +%Y%m%dT%H%M%SZ | tr '[:upper:]' '[:lower:]')"
  NAMESPACE="${K8S_NAMESPACE:-demo-prod}"
  REGION="${AWS_REGION:-us-east-1}"
  EVIDENCE_FILE="${EVIDENCE_DIR}/vuln-${vuln_id}-${STAMP}.txt"
  EVIDENCE_JSON="${EVIDENCE_DIR}/vuln-${vuln_id}-${STAMP}.json"
  mkdir -p "$EVIDENCE_DIR"
}

vuln_fail() {
  echo "FAIL: $*" >&2
  exit 1
}

vuln_alb_host() {
  if [[ -n "${BACKEND_URL:-}" ]]; then
    local host="${BACKEND_URL#http://}"
    host="${host#https://}"
    host="${host%%/*}"
    printf '%s' "$host"
    return
  fi
  kubectl -n "${NAMESPACE}" get ingress taskvault-public-ingress \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true
}

vuln_record_artifact() {
  local vuln_id="$1"
  local artifact_path="$2"
  local matrix_file="${EVIDENCE_DIR}/vuln-matrix-latest.json"
  python3 - "$vuln_id" "$artifact_path" "$matrix_file" <<'PY'
import json, sys
from pathlib import Path
vuln_id, artifact, matrix_file = sys.argv[1:4]
path = Path(matrix_file)
data = json.loads(path.read_text()) if path.exists() else {"vulns": {}}
data.setdefault("vulns", {})[vuln_id] = artifact
path.write_text(json.dumps(data, indent=2) + "\n")
PY
}
