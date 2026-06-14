# CI/CD (M12)

GitHub Actions workflows for TaskVault demo. See [spec §5.4](../README.md#54-workflows).

## Workflows

| File | Trigger | Purpose |
|------|---------|---------|
| `build.yml` | push, PR, `workflow_dispatch` | **T176** — test, build, docker push to ECR (OIDC). Tight `permissions`. |
| `security-scan.yml` | push, PR, `workflow_dispatch` | **T177/T182** — Trivy, Grype, Syft SBOM, Gitleaks, Checkov, Kubescape artifacts. **No gate.** |
| `deploy.yml` | push `main`, `workflow_dispatch` | **T178** — vuln-10 weak deploy (`write-all`, `@main` action). **No signing, no scan-gate.** |

## Repository configuration

Set GitHub repository **Variables**:

| Variable | Example |
|----------|---------|
| `AWS_OIDC_ROLE_ARN` | `arn:aws:iam::123456789012:role/taskvault-github-deploy-role` |

Prerequisites:

- CDK `TaskvaultGithubOidc` deployed (T140) with broad `repo:<org>/taskvault-demo:*` trust (**T179** intentional weakness)
- ECR repos + EKS cluster live (M8/M9)

## OIDC (T179)

Both `build.yml` and `deploy.yml` use:

```yaml
aws-actions/configure-aws-credentials@v4
  role-to-assume: ${{ vars.AWS_OIDC_ROLE_ARN }}
```

The AWS role trust allows **any branch/ref** in the repo (`taskvault-demo:*`) — required for the vuln-10 demo narrative.

## Triggers (T180)

- **build** + **security-scan**: every push and PR
- **deploy**: push to `main` only (+ manual `workflow_dispatch`)

On PRs, `build.yml` runs tests and `docker build` but skips ECR push (no AWS on forks).

## Pipeline verification (T184)

After pushing to `main`:

```bash
export GITHUB_REPOSITORY=<org>/taskvault-demo
export GITHUB_SHA=<commit-sha>
make ci-verify-pipeline
```

Or with `gh`:

```bash
gh run list --branch main
gh run download <run-id> -n security-scan-<sha> -D artifacts/sample/
```

Confirm:

1. `build` job green; ECR images tagged with commit SHA
2. `security-scan` uploads `trivy-backend.json`, `grype-backend.json`, `sbom-backend.spdx.json`, `gitleaks.json`, `checkov.json`, `kubescape.json`
3. `deploy` job green; `kubectl get deploy backend-api -n demo-prod` shows image `.../taskvault-backend:<sha>`

## vuln-10 contrast

| Control | `build.yml` (good) | `deploy.yml` (weak) |
|---------|-------------------|---------------------|
| GitHub `permissions` | `id-token` + `contents: read` | `write-all` |
| Third-party actions | pinned versions (`@v4`) | `nick-fields/retry@main` |
| Scan gate | N/A | **Absent** (T183) |
| Image signing | N/A | **Absent** — no cosign (T183) |

Documented in `docs/intentional-risks.md` § vuln-10.
