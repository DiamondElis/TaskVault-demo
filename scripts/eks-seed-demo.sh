#!/usr/bin/env bash
# T158/T159 — Run demo seed Job on EKS (users, tasks, files, jobs, sensitive S3 fixtures).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/eks-render-overlay.sh
source "$REPO_ROOT/scripts/eks-render-overlay.sh"

CLUSTER_NAME="${EKS_CLUSTER_NAME:-taskvault-eks}"
REGION="${AWS_REGION:-us-east-1}"
NAMESPACE="${K8S_NAMESPACE:-demo-prod}"
TAG="${ECR_BOOTSTRAP_TAG:-bootstrap}"

aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION" >/dev/null
OVERLAY_BUILD="$(eks_render_overlay)"
trap 'rm -rf "$OVERLAY_BUILD"' EXIT

# shellcheck source=scripts/cdk-outputs.sh
source "$REPO_ROOT/scripts/cdk-outputs.sh"
export_value BACKEND_REPO TaskvaultEcr BackendRepoUri
SEED_IMAGE="${BACKEND_REPO}:${TAG}-migrator"

JOB_NAME="seed-demo-$(date +%s)"
cat <<EOF | kubectl -n "$NAMESPACE" apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: ${JOB_NAME}
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/name: taskvault
    app.kubernetes.io/component: seed-demo
    app.kubernetes.io/part-of: taskvault-demo
spec:
  backoffLimit: 2
  ttlSecondsAfterFinished: 3600
  template:
    metadata:
      labels:
        app.kubernetes.io/name: taskvault
        app.kubernetes.io/component: seed-demo
    spec:
      serviceAccountName: backend-sa
      restartPolicy: Never
      containers:
        - name: seed-demo
          image: ${SEED_IMAGE}
          imagePullPolicy: Always
          command: ["node", "dist/src/db/seed-only.js"]
          envFrom:
            - configMapRef:
                name: app-config
            - configMapRef:
                name: backend-config
          env:
            - name: USE_SECRETS_MANAGER
              value: "true"
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 512Mi
EOF

echo "Waiting for seed Job ${JOB_NAME}..."
kubectl -n "$NAMESPACE" wait --for=condition=complete "job/${JOB_NAME}" --timeout=300s
kubectl -n "$NAMESPACE" logs "job/${JOB_NAME}"

export_value USER_FILES_BUCKET TaskvaultStorage UserFilesBucketName
echo ""
echo "Verifying sensitive fixtures in s3://${USER_FILES_BUCKET}/uploads/sensitive/ ..."
for key in payroll-export-demo.csv customer-records-demo.csv internal-access-review-demo.csv; do
  aws s3api head-object --bucket "$USER_FILES_BUCKET" --key "uploads/sensitive/${key}" >/dev/null
  echo "✓ s3://${USER_FILES_BUCKET}/uploads/sensitive/${key}"
done

echo ""
echo "Demo seed complete on EKS."
