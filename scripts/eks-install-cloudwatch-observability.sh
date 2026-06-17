#!/usr/bin/env bash
# Install or repair amazon-cloudwatch-observability (Fluent Bit → /taskvault/* log groups).
# Idempotent — handles CFN drift when the add-on was deleted from the cluster.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/taskvault-aws.sh
source "$REPO_ROOT/scripts/lib/taskvault-aws.sh"

CLUSTER_NAME="${EKS_CLUSTER_NAME:-taskvault-eks}"
ADDON_NAME="amazon-cloudwatch-observability"
CONFIG_FILE="$REPO_ROOT/infra/cdk/lib/cloudwatch-application-log.conf"

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "ERROR: missing Fluent Bit config: $CONFIG_FILE"
  exit 1
fi

CONFIGURATION_VALUES="$(python3 - "$CONFIG_FILE" <<'PY'
import json
import sys
from pathlib import Path

application_log = Path(sys.argv[1]).read_text()
print(json.dumps({
    "containerLogs": {
        "enabled": True,
        "fluentBit": {
            "config": {
                "extraFiles": {
                    "application-log.conf": application_log,
                },
            },
        },
    },
}))
PY
)"

echo "Ensuring ${ADDON_NAME} on ${CLUSTER_NAME}..."
STATUS="$(taskvault_aws eks describe-addon \
  --cluster-name "$CLUSTER_NAME" \
  --addon-name "$ADDON_NAME" \
  --query 'addon.status' \
  --output text 2>/dev/null || echo NOT_FOUND)"

if [[ "$STATUS" == "NOT_FOUND" ]]; then
  echo "Creating add-on (was missing from cluster)..."
  taskvault_aws eks create-addon \
    --cluster-name "$CLUSTER_NAME" \
    --addon-name "$ADDON_NAME" \
    --resolve-conflicts OVERWRITE \
    --configuration-values "$CONFIGURATION_VALUES"
else
  echo "Updating add-on (status: ${STATUS})..."
  taskvault_aws eks update-addon \
    --cluster-name "$CLUSTER_NAME" \
    --addon-name "$ADDON_NAME" \
    --resolve-conflicts OVERWRITE \
    --configuration-values "$CONFIGURATION_VALUES"
fi

echo "Waiting for add-on to become ACTIVE..."
for _ in $(seq 1 60); do
  STATUS="$(taskvault_aws eks describe-addon \
    --cluster-name "$CLUSTER_NAME" \
    --addon-name "$ADDON_NAME" \
    --query 'addon.status' \
    --output text 2>/dev/null || echo UNKNOWN)"
  if [[ "$STATUS" == "ACTIVE" ]]; then
    break
  fi
  if [[ "$STATUS" == "CREATE_FAILED" || "$STATUS" == "DEGRADED" ]]; then
    echo "ERROR: add-on status ${STATUS}"
    taskvault_aws eks describe-addon \
      --cluster-name "$CLUSTER_NAME" \
      --addon-name "$ADDON_NAME" \
      --query 'addon.{status:status,health:health}' \
      --output json || true
    exit 1
  fi
  sleep 10
done

[[ "$STATUS" == "ACTIVE" ]] || { echo "ERROR: add-on did not reach ACTIVE (last: ${STATUS})"; exit 1; }

echo "Waiting for Fluent Bit pods..."
kubectl wait --for=condition=ready pod \
  -l app.kubernetes.io/name=fluent-bit \
  -n amazon-cloudwatch \
  --timeout=180s 2>/dev/null || kubectl get pods -n amazon-cloudwatch -o wide

echo "✓ CloudWatch observability add-on ready"
