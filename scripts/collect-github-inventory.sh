#!/usr/bin/env bash
# T191 — GitHub/repo inventory collector (workflows, Dockerfiles, manifests).
set -euo pipefail
source "$(dirname "$0")/lib/export-evidence-common.sh"
export_evidence_init

OUTPUT="${ARTIFACT_DIR}/github-inventory.json"

python3 - "$OUTPUT" "$REPO_ROOT" <<'PY'
import json, os, subprocess, sys
from datetime import datetime, timezone
from pathlib import Path

out_path, repo_root = sys.argv[1:3]
root = Path(repo_root)

def git(*args):
    r = subprocess.run(["git", "-C", repo_root, *args], capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else None

def rel_glob(pattern):
    return sorted(str(p.relative_to(root)) for p in root.glob(pattern))

workflows_dir = root / ".github" / "workflows"
workflows = []
if workflows_dir.is_dir():
    for wf in sorted(workflows_dir.glob("*.yml")) + sorted(workflows_dir.glob("*.yaml")):
        text = wf.read_text()
        workflows.append({
            "path": str(wf.relative_to(root)),
            "name": wf.stem,
            "permissions_write_all": "permissions: write-all" in text.split("jobs:")[0],
            "unpinned_main_action": "@main" in text,
            "needs_security_scan": "needs:" in text and "security-scan" in text,
            "cosign": "cosign" in text.lower(),
        })

inv = {
    "schema_version": "1.0",
    "collected_at": datetime.now(timezone.utc).isoformat(),
    "repository": {
        "root": repo_root,
        "remote_origin": git("remote", "get-url", "origin"),
        "branch": git("rev-parse", "--abbrev-ref", "HEAD"),
        "commit": git("rev-parse", "HEAD"),
    },
    "workflows": workflows,
    "dockerfiles": rel_glob("**/Dockerfile"),
    "k8s_manifests": rel_glob("k8s/**/*.yaml") + rel_glob("k8s/**/*.yml"),
    "env_example": ".env.example" if (root / ".env.example").is_file() else None,
    "fake_secret_fixtures": [
        p for p in [".env.example", "backend/test/fixtures/fake-secrets.txt"]
        if (root / p).is_file()
    ],
}

with open(out_path, "w") as f:
    json.dump(inv, f, indent=2)
    f.write("\n")
print(f"Wrote {out_path} ({len(workflows)} workflows, {len(inv['dockerfiles'])} Dockerfiles)")
PY

assert_nonempty "$OUTPUT" "github-inventory.json"
