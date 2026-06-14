#!/usr/bin/env bash
set -euo pipefail

echo "Bootstrapping LocalStack resources for TaskVault demo..."

awslocal s3 mb s3://taskvault-user-files 2>/dev/null || true
awslocal s3 mb s3://taskvault-reports 2>/dev/null || true
awslocal sqs create-queue --queue-name taskvault-jobs 2>/dev/null || true

echo "LocalStack bootstrap complete."
