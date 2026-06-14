.PHONY: help local-up local-down docker-build scan-local cdk-synth cdk-deploy cdk-deploy-foundation \
	cdk-deploy-eks cdk-deploy-iam ecr-push-bootstrap eks-verify eks-verify-alb eks-verify-logs \
	eks-run-db-migrator eks-seed-demo smoke-eks eks-verify-irsa-s3 eks-verify-worker-flow \
	eks-verify-audit-coverage eks-verify-report-cronjob eks-deploy-seed-verify \
	verify-vuln-matrix compile-vuln-matrix ci-verify-pipeline \
	k8s-deploy k8s-lint kind-up kind-down kind-load-images k8s-local-up k8s-local-validate \
	k8s-kubescape seed-demo test-demo export-evidence destroy

# Docker Desktop's credential helper may be missing from PATH when /usr/local/bin symlink is stale.
export PATH := /Applications/Docker.app/Contents/Resources/bin:$(PATH)

COMPOSE := docker compose -f docker-compose.local.yml
DEFAULT_DATABASE_URL := postgres://demo:password@localhost:5432/taskvault
IMAGE_TAG := local

help:
	@echo "TaskVault demo targets:"
	@echo "  local-up         Start local dev stack (docker-compose)"
	@echo "  local-down       Stop local dev stack"
	@echo "  docker-build     Build container images"
	@echo "  scan-local       Run M11 vuln verification matrix (T165–T175)"
	@echo "  verify-vuln-matrix  Verify all ten intentional risks"
	@echo "  compile-vuln-matrix  T175: compile evidence table only"
	@echo "  ci-verify-pipeline  T184: verify CI build/deploy + scan artifacts"
	@echo "  cdk-synth        Synthesize CDK stacks"
	@echo "  cdk-deploy       Deploy all CDK stacks (foundation + EKS + IAM)"
	@echo "  cdk-deploy-foundation  Deploy network/KMS/ECR/storage/RDS/observability"
	@echo "  cdk-deploy-eks   Deploy EKS cluster + kubeconfig"
	@echo "  cdk-deploy-iam   Deploy IRSA + GitHub OIDC roles"
	@echo "  ecr-push-bootstrap  Push :bootstrap images to ECR"
	@echo "  eks-verify       Verify nodes, add-ons, OIDC, ALB controller"
	@echo "  eks-verify-alb   Verify internet ALB + vuln-1 debug route"
	@echo "  eks-verify-logs  Verify CloudWatch log flow"
	@echo "  eks-run-db-migrator  T157: run db-migrator Job on EKS"
	@echo "  eks-seed-demo    T158/T159: seed demo data + sensitive S3 fixtures on EKS"
	@echo "  smoke-eks        T160: end-to-end flow via ALB"
	@echo "  eks-verify-irsa-s3   T161: CloudTrail IRSA + S3 evidence"
	@echo "  eks-verify-worker-flow  T162: worker SQS/S3/RDS audit evidence"
	@echo "  eks-verify-audit-coverage  T163: required audit event_types"
	@echo "  eks-verify-report-cronjob  T164: report-cronjob → taskvault-reports"
	@echo "  eks-deploy-seed-verify  Full M10 validation chain (after k8s-deploy)"
	@echo "  k8s-deploy       Apply overlays/eks to taskvault-eks"
	@echo "  k8s-lint         Validate k8s manifests (kubeconform)"
	@echo "  kind-up          Create kind cluster + ingress + infra"
	@echo "  kind-down        Delete kind cluster"
	@echo "  kind-load-images Load taskvault-*:local into kind"
	@echo "  k8s-local-up     Apply k8s/overlays/local to kind"
	@echo "  k8s-local-validate  Verify workloads + vuln-3/5/7 on kind"
	@echo "  k8s-kubescape    Run kubescape against kind cluster"
	@echo "  seed-demo        Run DB migrations + demo seed (local or SEED_TARGET=eks)"
	@echo "  test-demo        Run demo validation tests"
	@echo "  export-evidence  Export inventories and scanner artifacts"
	@echo "  destroy          Tear down AWS demo environment"

local-up: docker-build
	@echo "Starting infrastructure (Postgres + LocalStack)..."
	$(COMPOSE) up -d postgres localstack
	@echo "Waiting for Postgres..."
	@until docker exec taskvault-postgres pg_isready -U demo -d taskvault >/dev/null 2>&1; do sleep 1; done
	@echo "Waiting for LocalStack..."
	@until curl -sf http://localhost:4566/_localstack/health | grep -qE '"s3": "(available|running)"'; do sleep 2; done
	@echo "Waiting for LocalStack S3/SQS bootstrap..."
	@until docker exec taskvault-localstack awslocal s3 ls s3://taskvault-user-files >/dev/null 2>&1 \
		&& docker exec taskvault-localstack awslocal sqs get-queue-url --queue-name taskvault-jobs >/dev/null 2>&1; do sleep 2; done
	@echo "Running database migrations + seed (db-migrator entrypoint)..."
	$(COMPOSE) run --rm --no-deps db-migrator
	@echo "Starting application services..."
	$(COMPOSE) up -d --wait backend worker frontend
	@echo "TaskVault local stack is ready."

local-down:
	$(COMPOSE) down -v

docker-build:
	docker build -t taskvault-backend:$(IMAGE_TAG) -f backend/Dockerfile --target stage-1 .
	docker build -t taskvault-backend-migrator:$(IMAGE_TAG) -f backend/Dockerfile --target migrator .
	docker build -t taskvault-worker:$(IMAGE_TAG) -f worker/Dockerfile .
	docker build -t taskvault-frontend:$(IMAGE_TAG) -f frontend/Dockerfile .

scan-local:
	chmod +x scripts/verify-vuln-matrix.sh scripts/verify-vuln-*.sh scripts/compile-vuln-matrix.sh
	./scripts/verify-vuln-matrix.sh

CDK_DIR := infra/cdk

cdk-synth:
	cd $(CDK_DIR) && npm install && npm run build
	cd $(CDK_DIR) && CDK_DEFAULT_ACCOUNT=$${CDK_DEFAULT_ACCOUNT:-111111111111} CDK_DEFAULT_REGION=us-east-1 npx cdk synth --quiet --no-lookups
	chmod +x scripts/cdk-checkov.sh
	./scripts/cdk-checkov.sh

cdk-deploy:
	chmod +x scripts/cdk-deploy.sh scripts/cdk-deploy-foundation.sh scripts/cdk-deploy-eks.sh scripts/cdk-deploy-iam.sh
	./scripts/cdk-deploy.sh

cdk-deploy-foundation:
	chmod +x scripts/cdk-deploy-foundation.sh scripts/cdk-outputs.sh
	./scripts/cdk-deploy-foundation.sh

cdk-deploy-eks:
	chmod +x scripts/cdk-deploy-eks.sh
	./scripts/cdk-deploy-eks.sh

cdk-deploy-iam:
	chmod +x scripts/cdk-deploy-iam.sh scripts/cdk-outputs.sh
	./scripts/cdk-deploy-iam.sh

ecr-push-bootstrap:
	chmod +x scripts/ecr-push-bootstrap.sh scripts/cdk-outputs.sh
	./scripts/ecr-push-bootstrap.sh

eks-verify:
	chmod +x scripts/eks-verify-cluster.sh scripts/cdk-outputs.sh
	./scripts/eks-verify-cluster.sh

eks-verify-alb:
	chmod +x scripts/eks-verify-alb.sh
	./scripts/eks-verify-alb.sh

eks-verify-logs:
	chmod +x scripts/eks-verify-logs.sh
	./scripts/eks-verify-logs.sh

eks-run-db-migrator:
	chmod +x scripts/eks-run-db-migrator.sh scripts/eks-render-overlay.sh scripts/cdk-outputs.sh
	./scripts/eks-run-db-migrator.sh

eks-seed-demo:
	chmod +x scripts/eks-seed-demo.sh scripts/eks-render-overlay.sh scripts/cdk-outputs.sh
	./scripts/eks-seed-demo.sh

smoke-eks:
	chmod +x scripts/smoke-eks.sh
	./scripts/smoke-eks.sh

eks-verify-irsa-s3:
	chmod +x scripts/eks-verify-irsa-s3.sh scripts/cdk-outputs.sh
	./scripts/eks-verify-irsa-s3.sh

eks-verify-worker-flow:
	chmod +x scripts/eks-verify-worker-flow.sh
	./scripts/eks-verify-worker-flow.sh

eks-verify-audit-coverage:
	chmod +x scripts/eks-verify-audit-coverage.sh
	./scripts/eks-verify-audit-coverage.sh

eks-verify-report-cronjob:
	chmod +x scripts/eks-verify-report-cronjob.sh scripts/cdk-outputs.sh
	./scripts/eks-verify-report-cronjob.sh

eks-deploy-seed-verify: eks-run-db-migrator eks-seed-demo smoke-eks eks-verify-irsa-s3 eks-verify-worker-flow eks-verify-audit-coverage eks-verify-report-cronjob
	@echo "M10 deploy & seed verification complete."

k8s-deploy:
	chmod +x scripts/k8s-eks-deploy.sh scripts/cdk-outputs.sh
	./scripts/k8s-eks-deploy.sh

k8s-lint:
	chmod +x scripts/k8s-lint.sh
	./scripts/k8s-lint.sh local
	./scripts/k8s-lint.sh eks

kind-up:
	chmod +x scripts/kind-up.sh scripts/kind-host-gateway.sh scripts/kind-connect-infra.sh
	./scripts/kind-up.sh

kind-down:
	chmod +x scripts/kind-down.sh
	./scripts/kind-down.sh

kind-load-images:
	chmod +x scripts/kind-load-images.sh
	./scripts/kind-load-images.sh

k8s-local-up:
	chmod +x scripts/k8s-local-up.sh scripts/kind-load-images.sh scripts/kind-connect-infra.sh
	./scripts/k8s-local-up.sh

k8s-local-validate:
	chmod +x scripts/k8s-local-validate.sh
	./scripts/k8s-local-validate.sh

k8s-kubescape:
	chmod +x scripts/k8s-kubescape.sh
	./scripts/k8s-kubescape.sh

seed-demo:
	@test -f .env || (cp .env.example .env && echo "Created .env from .env.example")
	@test -d backend/node_modules || (cd backend && npm install)
	backend/node_modules/.bin/tsx scripts/seed-demo-data.ts

test-demo:
	./scripts/smoke-local.sh

export-evidence:
	./scripts/export-evidence.sh

destroy:
	@echo "TODO: destroy"

verify-vuln-matrix:
	chmod +x scripts/verify-vuln-matrix.sh scripts/verify-vuln-*.sh scripts/compile-vuln-matrix.sh scripts/vuln-evidence-common.sh scripts/cdk-outputs.sh
	./scripts/verify-vuln-matrix.sh

compile-vuln-matrix:
	chmod +x scripts/compile-vuln-matrix.sh
	./scripts/compile-vuln-matrix.sh

ci-verify-pipeline:
	chmod +x scripts/ci-verify-pipeline.sh
	./scripts/ci-verify-pipeline.sh
