#!/usr/bin/env bash
# dev-destroy.sh destroys the dev stack, then runs the orphan audit.
#
# Run it at the end of every session. The bootstrap layer (state bucket,
# IAM, Spot role) has its own state and is never touched here.
#
# It exits 0 when the destroy worked and the audit found nothing left,
# and 1 otherwise.

# -e : exit immediately when any command fails
# -u : treat undefined variables as errors
# -o pipefail : fail a pipeline if any command in it fails
set -euo pipefail

export AWS_REGION="ap-southeast-1"
EXPECTED_ACCOUNT="471934606798"
REPO_ROOT=$(git rev-parse --show-toplevel)
DEV_DIR="$REPO_ROOT/infra/terraform/environments/dev"
TFVARS="dev.tfvars"

log() { echo "$(date -u +%FT%TZ) $*"; }
fail() { log "ERROR: $*"; exit 1; }

# ---------- 1. Preflight ----------
for tool in aws terraform git; do
  command -v "$tool" >/dev/null || fail "$tool is not installed"
done

ACCOUNT=$(aws sts get-caller-identity --query Account --output text) \
  || fail "the AWS CLI has no valid credentials"
if [ "$ACCOUNT" != "$EXPECTED_ACCOUNT" ]; then
  fail "the AWS CLI is on account $ACCOUNT, expected $EXPECTED_ACCOUNT"
fi
log "Preflight OK, account $ACCOUNT, region $AWS_REGION"

# ---------- 2. Terraform destroy ----------
cd "$DEV_DIR"
log "Running terraform destroy in $DEV_DIR"
terraform destroy -var-file="$TFVARS"

# After a full destroy the state should hold nothing. Anything still
# listed is a resource Terraform failed to delete.
LEFT=$(terraform state list | wc -l)
if [ "$LEFT" -ne 0 ]; then
  terraform state list
  fail "$LEFT resources are still in the state"
fi
log "Terraform state is empty"

# ---------- 3. Orphan audit ----------
# Catches anything created outside Terraform, or left behind by a
# failed delete that the state no longer knows about.
"$REPO_ROOT/scripts/orphan-audit.sh"
