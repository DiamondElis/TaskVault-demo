#!/usr/bin/env bash
# Full CDK deploy in dependency order (T146 → T149).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$REPO_ROOT/scripts/cdk-deploy-foundation.sh"
"$REPO_ROOT/scripts/cdk-deploy-eks.sh"
"$REPO_ROOT/scripts/cdk-deploy-iam.sh"

echo ""
echo "All CDK stacks deployed."
