#!/usr/bin/env bash
# T191 — AWS inventory collector (account/VPC/EKS/IAM/S3/RDS/ECR/ALB/CloudTrail).
set -euo pipefail
source "$(dirname "$0")/lib/export-evidence-common.sh"
export_evidence_init

# shellcheck source=scripts/lib/taskvault-aws.sh
source "${REPO_ROOT}/scripts/lib/taskvault-aws.sh" 2>/dev/null || true
# shellcheck source=scripts/cdk-outputs.sh
source "${REPO_ROOT}/scripts/cdk-outputs.sh" 2>/dev/null || true

OUTPUT="${ARTIFACT_DIR}/aws-inventory.json"
CLUSTER_NAME="${EKS_CLUSTER_NAME:-taskvault-eks}"

python3 - "$OUTPUT" "$REPO_ROOT" "$REGION" "$NAMESPACE" "$CLUSTER_NAME" <<'PY'
import json, os, subprocess, sys
from datetime import datetime, timezone

out_path, repo_root, region, namespace, cluster_name = sys.argv[1:6]
profile = os.environ.get("AWS_PROFILE", "taskvault-deploy")

def aws(*args, check=False):
    cmd = ["aws", "--profile", profile, "--region", region, *args, "--output", "json"]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        if check:
            raise RuntimeError(r.stderr.strip() or r.stdout.strip())
        return None
    if not r.stdout.strip():
        return None
    try:
        return json.loads(r.stdout)
    except json.JSONDecodeError:
        return r.stdout.strip()

def cfn_output(stack, key):
    data = aws("cloudformation", "describe-stacks", "--stack-name", stack)
    if not data:
        return None
    for o in data.get("Stacks", [{}])[0].get("Outputs", []):
        if o.get("OutputKey") == key:
            return o.get("OutputValue")
    return None

inv = {
    "schema_version": "1.0",
    "collected_at": datetime.now(timezone.utc).isoformat(),
    "region": region,
    "profile": profile,
    "account": None,
    "vpc": {},
    "eks": {},
    "iam": {"roles": []},
    "s3": {"buckets": []},
    "rds": {},
    "ecr": {"repositories": []},
    "alb": {},
    "cloudtrail": {},
    "errors": [],
}

identity = aws("sts", "get-caller-identity")
if identity:
    inv["account"] = identity.get("Account")
else:
    inv["errors"].append("sts get-caller-identity unavailable")

vpc_id = cfn_output("TaskvaultNetwork", "VpcId")
if vpc_id:
    inv["vpc"]["id"] = vpc_id
    inv["vpc"]["security_groups"] = {
        "alb": cfn_output("TaskvaultNetwork", "AlbSecurityGroupId"),
        "rds": cfn_output("TaskvaultNetwork", "RdsSecurityGroupId"),
        "node": cfn_output("TaskvaultNetwork", "NodeSecurityGroupId"),
    }
    subnets = aws("ec2", "describe-subnets", "--filters", f"Name=vpc-id,Values={vpc_id}")
    if subnets:
        inv["vpc"]["subnets"] = [
            {"id": s["SubnetId"], "az": s["AvailabilityZone"], "public": s.get("MapPublicIpOnLaunch", False)}
            for s in subnets.get("Subnets", [])
        ]

cluster = aws("eks", "describe-cluster", "--name", cluster_name)
if cluster:
    c = cluster.get("cluster", {})
    inv["eks"] = {
        "name": c.get("name"),
        "arn": c.get("arn"),
        "version": c.get("version"),
        "status": c.get("status"),
        "oidc_issuer": c.get("identity", {}).get("oidc", {}).get("issuer"),
        "endpoint": c.get("endpoint"),
    }
else:
    inv["eks"] = {
        "name": cluster_name,
        "status": "unavailable",
        "oidc_issuer": cfn_output("TaskvaultEks", "ClusterOidcIssuer"),
    }

for stack, key, role_key in [
    ("TaskvaultIam", "BackendRoleArn", "taskvault-backend-role"),
    ("TaskvaultIam", "WorkerRoleArn", "taskvault-worker-role"),
    ("TaskvaultGithubOidc", "GithubDeployRoleArn", "taskvault-github-deploy-role"),
]:
    arn = cfn_output(stack, key)
    if arn:
        inv["iam"]["roles"].append({"name": role_key, "arn": arn, "stack": stack})

for bucket_key in ("UserFilesBucketName", "ReportsBucketName"):
    name = cfn_output("TaskvaultStorage", bucket_key)
    if name:
        versioning = aws("s3api", "get-bucket-versioning", "--bucket", name) or {}
        inv["s3"]["buckets"].append({
            "name": name,
            "versioning": versioning.get("Status", "Disabled"),
        })

inv["rds"] = {
    "endpoint": cfn_output("TaskvaultRds", "DbEndpoint"),
    "secret_arn": cfn_output("TaskvaultRds", "DbSecretArn"),
}

for repo_name in ("taskvault-frontend", "taskvault-backend", "taskvault-worker"):
    repos = aws("ecr", "describe-repositories", "--repository-names", repo_name)
    if repos and repos.get("repositories"):
        r = repos["repositories"][0]
        inv["ecr"]["repositories"].append({
            "name": r.get("repositoryName"),
            "uri": r.get("repositoryUri"),
        })

# ALB from live ingress if kubeconfig works
try:
    r = subprocess.run(
        ["kubectl", "-n", namespace, "get", "ingress", "taskvault-public-ingress",
         "-o", "jsonpath={.status.loadBalancer.ingress[0].hostname}"],
        capture_output=True, text=True, check=False,
    )
    alb_host = r.stdout.strip()
    if alb_host:
        inv["alb"]["hostname"] = alb_host
        inv["alb"]["internet_facing"] = True
        lbs = aws("elbv2", "describe-load-balancers")
        if lbs:
            for lb in lbs.get("LoadBalancers", []):
                if alb_host.startswith(lb.get("DNSName", "").split(".")[0]):
                    inv["alb"]["arn"] = lb.get("LoadBalancerArn")
                    inv["alb"]["scheme"] = lb.get("Scheme")
                    break
except Exception as e:
    inv["errors"].append(f"alb lookup: {e}")

trail = aws("cloudtrail", "describe-trails")
if trail:
    for t in trail.get("trailList", []):
        if "taskvault" in t.get("Name", "").lower():
            inv["cloudtrail"] = {
                "name": t.get("Name"),
                "arn": t.get("TrailARN"),
                "s3_bucket": t.get("S3BucketName"),
                "is_multi_region": t.get("IsMultiRegionTrail"),
            }
            break
if not inv["cloudtrail"]:
    inv["cloudtrail"]["arn"] = cfn_output("TaskvaultObservability", "CloudTrailArn")

with open(out_path, "w") as f:
    json.dump(inv, f, indent=2)
    f.write("\n")
print(f"Wrote {out_path}")
PY

assert_nonempty "$OUTPUT" "aws-inventory.json"
