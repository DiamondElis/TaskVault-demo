#!/usr/bin/env bash
# T173 — vuln-9: S3 versioning disabled + sensitive prefix fixtures present.
set -euo pipefail
source "$(dirname "$0")/vuln-evidence-common.sh"
source "$(dirname "$0")/cdk-outputs.sh"
vuln_evidence_init "09"
exec > >(tee "$EVIDENCE_FILE") 2>&1

export_value USER_BUCKET TaskvaultStorage UserFilesBucketName

echo "=== T173 / vuln-9 — versioning off + sensitive prefix ==="
echo "Bucket: ${USER_BUCKET}"

VERSIONING="$(aws s3api get-bucket-versioning --bucket "$USER_BUCKET" --region "$REGION" --output json)"
echo "$VERSIONING" | tee "${EVIDENCE_DIR}/vuln-09-versioning-${STAMP}.json"
STATUS="$(echo "$VERSIONING" | python3 -c "import json,sys; print(json.load(sys.stdin).get('Status','Disabled'))")"
if [[ -n "$STATUS" && "$STATUS" != "None" ]]; then
  vuln_fail "expected versioning disabled, got Status=${STATUS}"
fi
echo "✓ bucket versioning disabled (vuln-9 IaC half)"

echo ""
echo "--- uploads/sensitive/ fixtures ---"
OBJECTS="$(aws s3api list-objects-v2 --bucket "$USER_BUCKET" --prefix uploads/sensitive/ \
  --query 'Contents[].Key' --output text --region "$REGION")"
echo "$OBJECTS" | tee "${EVIDENCE_DIR}/vuln-09-objects-${STAMP}.txt"
for key in payroll-export-demo.csv customer-records-demo.csv internal-access-review-demo.csv; do
  echo "$OBJECTS" | grep -q "$key" || vuln_fail "missing fixture uploads/sensitive/${key}"
  echo "✓ uploads/sensitive/${key}"
done

python3 - "$EVIDENCE_JSON" <<'PY'
import json, sys
from pathlib import Path
Path(sys.argv[1]).write_text(json.dumps({
  "vuln_id": "vuln-9",
  "task": "T173",
  "versioning": "disabled",
  "sensitive_prefix": "uploads/sensitive/",
  "verified": True,
}, indent=2) + "\n")
PY

vuln_record_artifact "vuln-9" "$EVIDENCE_FILE"
echo "✓ T173 evidence: ${EVIDENCE_FILE}"
