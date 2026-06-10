# Contributing to TaskVault Demo

## One task, one commit

Each task in the build specification (T001, T002, …) should land as **one focused commit** with a message that references the task ID (e.g. `T004: stub Makefile targets`). Keep commits small and reviewable; do not batch unrelated work.

## Intentional risk labeling

Any deliberate security weakness must be:

1. **Labeled in Kubernetes** with `cnapp.demo/intentional-risk: "true"` and `cnapp.demo/risk-id: "<id>"` (e.g. `vuln-3`).
2. **Documented** in `docs/intentional-risks.md` with the risk ID, detection surface, and file locations.

Use the `cnapp.demo/intentional-risk` and `cnapp.demo/risk-id` label convention consistently so auditors and the CNAPP can distinguish demo risks from accidental misconfigurations.

## Pull requests

- Link the task ID in the PR description.
- Do not introduce real secrets, PII, or exploit payloads.
- Run `make test-demo` (when implemented) before requesting review.
