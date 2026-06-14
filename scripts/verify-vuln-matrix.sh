#!/usr/bin/env bash
# M11 orchestrator — run all vuln verification scripts (T165–T174).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

chmod +x scripts/verify-vuln-*.sh scripts/compile-vuln-matrix.sh scripts/vuln-evidence-common.sh scripts/cdk-outputs.sh

RUN_VULN="${RUN_VULN:-all}"
run_one() {
  local script="$1"
  echo ""
  echo ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
  echo "Running ${script}"
  echo ">>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>"
  "./scripts/${script}"
}

case "$RUN_VULN" in
  all)
    for id in 01 02 03 04 05 06 07 08 09 10; do
      run_one "verify-vuln-${id}.sh"
    done
    ;;
  [0-9]|10)
    run_one "verify-vuln-$(printf '%02d' "$RUN_VULN").sh"
    ;;
  vuln-*)
    num="${RUN_VULN#vuln-}"
    run_one "verify-vuln-$(printf '%02d' "$num").sh"
    ;;
  *)
    echo "Usage: RUN_VULN=all|1..10|vuln-N ./scripts/verify-vuln-matrix.sh" >&2
    exit 1
    ;;
esac

if [[ "$RUN_VULN" == "all" ]]; then
  ./scripts/compile-vuln-matrix.sh
fi
