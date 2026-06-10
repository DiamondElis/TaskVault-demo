.PHONY: help local-up local-down docker-build scan-local cdk-synth cdk-deploy k8s-deploy seed-demo test-demo export-evidence destroy

help:
	@echo "TaskVault demo targets:"
	@echo "  local-up         Start local dev stack (docker-compose)"
	@echo "  local-down       Stop local dev stack"
	@echo "  docker-build     Build container images"
	@echo "  scan-local       Run local security scanners"
	@echo "  cdk-synth        Synthesize CDK stacks"
	@echo "  cdk-deploy       Deploy AWS infrastructure via CDK"
	@echo "  k8s-deploy       Deploy workloads to EKS"
	@echo "  seed-demo        Seed demo data (DB + S3 fixtures)"
	@echo "  test-demo        Run demo validation tests"
	@echo "  export-evidence  Export inventories and scanner artifacts"
	@echo "  destroy          Tear down AWS demo environment"

local-up:
	@echo "TODO: local-up"

local-down:
	@echo "TODO: local-down"

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
	@echo "TODO: seed-demo"

test-demo:
	@echo "TODO: test-demo"

export-evidence:
	@echo "TODO: export-evidence"

destroy:
	@echo "TODO: destroy"
