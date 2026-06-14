# Test plan

## Kubernetes — EndpointSlice presence (T103)

The CNAPP K8s connector maps `Service → EndpointSlice → Pod IP`. After deploying manifests, verify each ClusterIP Service generates EndpointSlices once backing pods are ready:

```bash
kubectl -n demo-prod get endpointslices -l kubernetes.io/service-name
kubectl -n demo-prod get endpointslices -l kubernetes.io/service-name=frontend-service -o yaml
kubectl -n demo-prod get endpointslices -l kubernetes.io/service-name=backend-service -o yaml
kubectl -n demo-prod get endpointslices -l kubernetes.io/service-name=worker-internal-service -o yaml
kubectl -n demo-prod get endpointslices -l kubernetes.io/service-name=metrics-service -o yaml
```

**Pass criteria:** each of `frontend-service`, `backend-service`, `worker-internal-service`, and `metrics-service` has at least one EndpointSlice with ready addresses when workloads are running.

<!-- Additional acceptance criteria — filled in M14. -->
