#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

CLUSTER_NAME="${KIND_CLUSTER_NAME:-taskvault}"
NAMESPACE="${K8S_NAMESPACE:-demo-prod}"
EVIDENCE_DIR="${EVIDENCE_DIR:-artifacts/sample}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ | tr '[:upper:]' '[:lower:]')"
EVIDENCE_FILE="${EVIDENCE_DIR}/k8s-local-validation-${STAMP}.txt"

mkdir -p "$EVIDENCE_DIR"
exec > >(tee "$EVIDENCE_FILE") 2>&1

kind export kubeconfig --name "$CLUSTER_NAME" >/dev/null 2>&1 || true

log() {
  echo ""
  echo "=== $* ==="
}

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

log "T114 — Workloads, services, EndpointSlices"
kubectl -n "$NAMESPACE" get deploy,pod,svc,ingress,endpointslices

for deploy in frontend backend-api worker; do
  ready="$(kubectl -n "$NAMESPACE" get deploy "$deploy" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)"
  desired="$(kubectl -n "$NAMESPACE" get deploy "$deploy" -o jsonpath='{.spec.replicas}')"
  if [[ "${ready:-0}" != "$desired" ]]; then
    fail "deployment/${deploy} not ready (${ready:-0}/${desired})"
  fi
  echo "✓ deployment/${deploy} ready (${ready}/${desired})"
done

for svc in frontend-service backend-service worker-internal-service metrics-service; do
  count="$(kubectl -n "$NAMESPACE" get endpointslices -l "kubernetes.io/service-name=${svc}" --no-headers 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "$count" -lt 1 ]]; then
    fail "no EndpointSlice for service/${svc}"
  fi
  echo "✓ EndpointSlice exists for ${svc}"
done

log "T115 — RBAC weakness (vuln-3)"
RBAC_OUT="$(kubectl auth can-i list secrets --as="system:serviceaccount:${NAMESPACE}:backend-sa" -n "$NAMESPACE")"
echo "kubectl auth can-i list secrets --as=system:serviceaccount:${NAMESPACE}:backend-sa -n ${NAMESPACE}"
echo "=> ${RBAC_OUT}"
if [[ "$RBAC_OUT" != "yes" ]]; then
  fail "expected backend-sa to list secrets (vuln-3)"
fi
echo "✓ vuln-3 verified: backend-sa can list secrets"

log "T116 — Privileged worker + hostPath (vuln-5)"
WORKER_POD="$(kubectl -n "$NAMESPACE" get pod -l app.kubernetes.io/component=worker \
  --field-selector=status.phase=Running \
  -o jsonpath='{.items[0].metadata.name}')"
kubectl -n "$NAMESPACE" get pod "$WORKER_POD" -o yaml | tee "${EVIDENCE_DIR}/k8s-worker-pod-${STAMP}.yaml" >/dev/null

privileged="$(kubectl -n "$NAMESPACE" get pod "$WORKER_POD" -o jsonpath='{.spec.containers[0].securityContext.privileged}')"
hostpath="$(kubectl -n "$NAMESPACE" get pod "$WORKER_POD" -o jsonpath='{.spec.volumes[?(@.hostPath)].hostPath.path}')"
echo "worker pod: ${WORKER_POD}"
echo "securityContext.privileged: ${privileged}"
echo "hostPath.path: ${hostpath}"
if [[ "$privileged" != "true" ]]; then
  fail "worker pod is not privileged"
fi
if [[ "$hostpath" != "/" ]]; then
  fail "worker pod missing hostPath mount of /"
fi
echo "✓ vuln-5 verified: privileged worker with hostPath /"

log "T117 — Missing default-deny NetworkPolicy (vuln-7)"
NETPOL_LIST="$(kubectl -n "$NAMESPACE" get networkpolicy -o name)"
echo "NetworkPolicies in ${NAMESPACE}:"
echo "${NETPOL_LIST:-<none>}"
if echo "$NETPOL_LIST" | grep -q 'default-deny'; then
  fail "unexpected default-deny NetworkPolicy present"
fi
echo "✓ no default-deny NetworkPolicy objects"

PROBE_POD="netpol-probe-${STAMP}"
kubectl -n "$NAMESPACE" run "$PROBE_POD" \
  --image=busybox:1.36 \
  --restart=Never \
  --command -- sleep 300
kubectl -n "$NAMESPACE" wait --for=condition=ready "pod/${PROBE_POD}" --timeout=60s

# backend-api has allow-frontend-to-backend ingress only; probe an unrestricted target instead.
if kubectl -n "$NAMESPACE" exec "$PROBE_POD" -- wget -q -O- http://frontend-service/health | grep -q '"status":"ok"'; then
  echo "✓ probe pod reached frontend-service (no default-deny blocking east-west)"
else
  kubectl -n "$NAMESPACE" delete pod "$PROBE_POD" --ignore-not-found
  fail "probe pod could not reach frontend-service (unexpected)"
fi
kubectl -n "$NAMESPACE" delete pod "$PROBE_POD" --ignore-not-found

echo ""
echo "Local K8s validation passed."
echo "Evidence saved to: ${EVIDENCE_FILE}"
