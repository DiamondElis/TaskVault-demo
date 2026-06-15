#!/usr/bin/env bash
# Wait until the EKS managed node group is stable: desired Ready workers, no stragglers.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/taskvault-aws.sh
source "$REPO_ROOT/scripts/lib/taskvault-aws.sh"

CLUSTER_NAME="${EKS_CLUSTER_NAME:-taskvault-eks}"
NODEGROUP_NAME="${EKS_NODEGROUP_NAME:-taskvault-ng}"
TIMEOUT_SEC="${EKS_NODE_WAIT_TIMEOUT:-900}"

resolve_desired_nodes() {
  if [[ -n "${EKS_DESIRED_NODES:-}" ]]; then
    echo "$EKS_DESIRED_NODES"
    return
  fi
  taskvault_aws eks describe-nodegroup \
    --cluster-name "$CLUSTER_NAME" \
    --nodegroup-name "$NODEGROUP_NAME" \
    --query 'nodegroup.scalingConfig.desiredSize' \
    --output text
}

echo "Waiting for node group ${NODEGROUP_NAME} on ${CLUSTER_NAME} (timeout ${TIMEOUT_SEC}s)..."
echo "  AWS profile: ${AWS_PROFILE}  region: ${AWS_REGION}"
taskvault_eks_update_kubeconfig "$CLUSTER_NAME"

DESIRED="$(resolve_desired_nodes)"
echo "  Target: ${DESIRED} Ready worker(s) in ${NODEGROUP_NAME} (no NotReady stragglers)"

nodegroup_counts() {
  local lines total ready notready
  lines="$(kubectl get nodes \
    -l "eks.amazonaws.com/nodegroup=${NODEGROUP_NAME}" \
    --no-headers 2>/dev/null || true)"
  if [[ -z "$lines" ]]; then
    echo "0 0 0"
    return
  fi
  total="$(printf '%s\n' "$lines" | sed '/^$/d' | wc -l | tr -d ' ')"
  ready="$(printf '%s\n' "$lines" | awk '$2=="Ready"{c++} END{print c+0}')"
  notready="$(printf '%s\n' "$lines" | awk '$2!="Ready"{c++} END{print c+0}')"
  echo "$total $ready $notready"
}

deadline=$((SECONDS + TIMEOUT_SEC))
while (( SECONDS < deadline )); do
  read -r total ready notready <<<"$(nodegroup_counts)"

  if [[ "$ready" == "0" && "$total" == "0" ]] && ! kubectl auth can-i get nodes --quiet 2>/dev/null; then
    echo "ERROR: kubectl cannot authenticate to ${CLUSTER_NAME}."
    echo "  Ensure IAM user '${AWS_PROFILE}' is mapped in aws-auth or has an EKS access entry."
    echo "  Redeploy EKS: export AWS_PROFILE=${AWS_PROFILE} && make cdk-deploy-eks"
    exit 1
  fi

  echo "  ${NODEGROUP_NAME}: ${ready}/${DESIRED} Ready, ${total} total, ${notready} NotReady"

  if [[ "$ready" -ge "$DESIRED" && "$total" -eq "$DESIRED" && "$notready" -eq 0 ]]; then
    kubectl get nodes -l "eks.amazonaws.com/nodegroup=${NODEGROUP_NAME}" -o wide
    exit 0
  fi

  sleep 15
done

echo "ERROR: timed out waiting for ${NODEGROUP_NAME} to stabilize (${DESIRED} Ready, no NotReady nodes)"
kubectl get nodes -l "eks.amazonaws.com/nodegroup=${NODEGROUP_NAME}" -o wide || kubectl get nodes -o wide || true
exit 1
