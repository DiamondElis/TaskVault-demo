# TaskVault Demo — Notice

This repository is an **intentionally vulnerable demonstration target** for CNAPP (Cloud-Native Application Protection Platform) evaluation and training.

## Demo-only use

- Deploy **only** in a dedicated, isolated AWS demo account (`taskvault-demo-prod`).
- Do **not** connect to production networks, VPCs, or data stores.
- Contains **no real credentials or customer data** — all secrets are syntactically valid but dead placeholders.

## Destruction required

This environment **must be destroyed after use**. Run `make destroy` and verify all AWS resources, ECR images, and cluster workloads are removed. Do not leave the demo running unattended.

## No warranty

See [LICENSE](LICENSE). This software is provided for demonstration purposes only.
