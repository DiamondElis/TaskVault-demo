.PHONY: help local-up local-down docker-build scan-local cdk-synth cdk-deploy k8s-deploy seed-demo test-demo export-evidence destroy

COMPOSE := docker compose -f docker-compose.local.yml
DEFAULT_DATABASE_URL := postgres://demo:password@localhost:5432/taskvault

help:
	@echo "TaskVault demo targets:"
	@echo "  local-up         Start local dev stack (docker-compose)"
	@echo "  local-down       Stop local dev stack"
	@echo "  docker-build     Build container images"
	@echo "  scan-local       Run local security scanners"
	@echo "  cdk-synth        Synthesize CDK stacks"
	@echo "  cdk-deploy       Deploy AWS infrastructure via CDK"
	@echo "  k8s-deploy       Deploy workloads to EKS"
	@echo "  seed-demo        Run DB migrations (idempotent) + demo seed stub"
	@echo "  test-demo        Run demo validation tests"
	@echo "  export-evidence  Export inventories and scanner artifacts"
	@echo "  destroy          Tear down AWS demo environment"

local-up:
	$(COMPOSE) up -d
	@echo "Postgres and LocalStack starting."

local-down:
	$(COMPOSE) down

docker-build:
	@echo "TODO: docker-build"

scan-local:
	@echo "TODO: scan-local"

cdk-synth:
	@echo "TODO: cdk-synth"

cdk-deploy:
	@echo "TODO: cdk-deploy"

k8s-deploy:
	@echo "TODO: k8s-deploy"

seed-demo:
	@test -f .env || (cp .env.example .env && echo "Created .env from .env.example")
	@test -d backend/node_modules || (cd backend && npm install)
	@$(COMPOSE) up -d postgres
	@echo "Waiting for Postgres..."
	@until docker exec taskvault-postgres pg_isready -U demo -d taskvault >/dev/null 2>&1; do sleep 1; done
	backend/node_modules/.bin/tsx scripts/seed-demo-data.ts

test-demo:
	./scripts/validate-demo.sh

export-evidence:
	./scripts/export-evidence.sh

destroy:
	@echo "TODO: destroy"
