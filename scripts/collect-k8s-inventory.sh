#!/usr/bin/env bash
# T191 — Kubernetes inventory collector (spec §4.3 API surface).
set -euo pipefail
source "$(dirname "$0")/lib/export-evidence-common.sh"
export_evidence_init

OUTPUT="${ARTIFACT_DIR}/k8s-inventory.json"
CLUSTER_NAME="${EKS_CLUSTER_NAME:-taskvault-eks}"

# shellcheck source=scripts/lib/taskvault-aws.sh
source "${REPO_ROOT}/scripts/lib/taskvault-aws.sh" 2>/dev/null || true
taskvault_eks_update_kubeconfig "$CLUSTER_NAME" 2>/dev/null || true

python3 - "$OUTPUT" "$NAMESPACE" "$CLUSTER_NAME" <<'PY'
import json, subprocess, sys
from datetime import datetime, timezone

out_path, namespace, cluster_name = sys.argv[1:4]

def kubectl_json(args, check=False):
    cmd = ["kubectl", *args, "-o", "json"]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        if check:
            raise RuntimeError(r.stderr.strip() or "kubectl failed")
        return {"items": [], "_error": r.stderr.strip()}
    if not r.stdout.strip():
        return {"items": []}
    return json.loads(r.stdout)

def get_list(kind_args, ns=None):
    args = list(kind_args)
    if ns:
        args.extend(["-n", ns])
    data = kubectl_json(args)
    items = data.get("items", [])
    if isinstance(data, dict) and "kind" in data and data.get("kind") != "List":
        return [data]
    return items

inv = {
    "schema_version": "1.0",
    "collected_at": datetime.now(timezone.utc).isoformat(),
    "cluster": cluster_name,
    "namespace": namespace,
    "resources": {},
    "errors": [],
}

# Core resources (namespace-scoped in demo-prod)
for key, args in [
    ("pods", ["get", "pods"]),
    ("services", ["get", "services"]),
    ("endpoints", ["get", "endpoints"]),
    ("serviceaccounts", ["get", "serviceaccounts"]),
    ("secrets", ["get", "secrets"]),
    ("configmaps", ["get", "configmaps"]),
    ("events", ["get", "events", "--field-selector", f"involvedObject.namespace={namespace}"]),
    ("deployments", ["get", "deployments"]),
    ("replicasets", ["get", "replicasets"]),
    ("jobs", ["get", "jobs"]),
    ("cronjobs", ["get", "cronjobs"]),
    ("ingresses", ["get", "ingresses"]),
    ("networkpolicies", ["get", "networkpolicies"]),
    ("roles", ["get", "roles"]),
    ("rolebindings", ["get", "rolebindings"]),
    ("persistentvolumeclaims", ["get", "persistentvolumeclaims"]),
]:
    inv["resources"][key] = get_list(args, namespace)

# Cluster-scoped / cross-namespace
for key, args in [
    ("namespaces", ["get", "namespaces"]),
    ("nodes", ["get", "nodes"]),
    ("persistentvolumes", ["get", "persistentvolumes"]),
    ("endpointslices", ["get", "endpointslices", "-l", "kubernetes.io/service-name"]),
    ("clusterroles", ["get", "clusterroles"]),
    ("clusterrolebindings", ["get", "clusterrolebindings"]),
    ("storageclasses", ["get", "storageclasses"]),
    ("csidrivers", ["get", "csidrivers"]),
    ("csinodes", ["get", "csinodes"]),
    ("validatingwebhookconfigurations", ["get", "validatingwebhookconfigurations"]),
    ("mutatingwebhookconfigurations", ["get", "mutatingwebhookconfigurations"]),
]:
    if key == "endpointslices":
        inv["resources"][key] = get_list(["get", "endpointslices", "-n", namespace])
    else:
        inv["resources"][key] = get_list(args)

# Metrics (optional)
metrics = kubectl_json(["get", "--raw", f"/apis/metrics.k8s.io/v1beta1/namespaces/{namespace}/pods"])
if isinstance(metrics, dict) and metrics.get("items") is not None:
    inv["resources"]["metrics_pods"] = metrics.get("items", [])
else:
    inv["resources"]["metrics_pods"] = []

# Summarize counts for quick oracle cross-check
inv["summary"] = {k: len(v) if isinstance(v, list) else 0 for k, v in inv["resources"].items()}

with open(out_path, "w") as f:
    json.dump(inv, f, indent=2)
    f.write("\n")
print(f"Wrote {out_path} ({inv['summary'].get('pods', 0)} pods in {namespace})")
PY

assert_nonempty "$OUTPUT" "k8s-inventory.json"
