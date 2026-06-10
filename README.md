# TaskVault — CNAPP demo target environment (intentionally vulnerable, demo-only)

## Overview

<!-- TODO: Describe TaskVault purpose, the 3-service architecture, and CNAPP demo goals. -->

## Safety guardrails

> **Safety guardrails (non-negotiable, baked into every section below):**
> - Fake credentials only. Every "secret" is a syntactically-valid-but-dead placeholder.
> - One **dedicated, isolated AWS account** (`taskvault-demo-prod`), single region (`us-east-1`), no shared VPC peering, no production data.
> - No real PII — only `*-demo.csv` fixtures with synthetic rows.
> - No exploit payloads. The vulnerabilities are *configuration weaknesses and posture findings*, not weaponized code.
> - Every intentional risk is labeled in-cluster (`cnapp.demo/intentional-risk: "true"`) and documented in `docs/intentional-risks.md`.
> - A `make destroy` path that fully tears the environment down.

## Repo layout

<!-- TODO: Document top-level directories (frontend, backend, worker, infra/cdk, k8s, scripts, docs, artifacts). -->

## Local run

<!-- TODO: Prerequisites, cp .env.example .env, make local-up, make seed-demo. -->

## Deploy to AWS

<!-- TODO: Account setup, make cdk-deploy, make k8s-deploy, validation steps. -->

## Cleanup

<!-- TODO: make destroy, account teardown checklist. See docs/cleanup.md. -->

## Intentional risks

<!-- TODO: Link to docs/intentional-risks.md and summarize the 10 vulns. -->

## Links

<!-- TODO: CNAPP docs, architecture.md, graph-contract.md, runbook.md. -->
