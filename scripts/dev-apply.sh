#!/usr/bin/env bash
# dev-apply.sh builds the dev stack and waits until the K3s node is usable.
#
# It does five things in order.
#   1. Checks the tools exist and the AWS CLI points at the right account.
#   2. Runs terraform init and apply in environments/dev. You type yes.
#   3. Waits for the K3s node to show Online in SSM, and reboots it once if not.
#   4. Waits for K3s to report the node Ready, checked through SSM.
#   5. Prints how long the rebuild took.
#
# It exits 0 when the node is Ready, and 1 if anything fails or times out.
# End every session with dev-destroy.sh and orphan-audit.sh.

# -e : exit immediately when any command fails
# -u : treat undefined variables as errors
# -o pipefail : fail a pipeline if any command in it fails
set -euo pipefail

# ---------- Settings ----------
export AWS_REGION="ap-southeast-1"
EXPECTED_ACCOUNT="471934606798"
REPO_ROOT=$(git rev-parse --show-toplevel)
DEV_DIR="$REPO_ROOT/infra/terraform/environments/dev"
TFVARS="dev.tfvars"

SSM_TIMEOUT=300    # seconds to wait for SSM Online, before and after the reboot
READY_TIMEOUT=600  # seconds to wait for K3s Ready (NAT setup plus K3s install)
POLL=15            # seconds between checks

START_TIME=$(date +%s)

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

# ---------- 2. Terraform apply ----------
cd "$DEV_DIR"
log "Running terraform init and apply in $DEV_DIR"
terraform init
terraform apply -var-file="$TFVARS"

INSTANCE_ID=$(terraform output -raw k3s_instance_id)
log "K3s instance is $INSTANCE_ID"

# ---------- 3. Wait for SSM Online ----------
# Returns 0 once SSM reports the node Online, 1 on timeout.
wait_for_ssm() {
  local waited=0 status
  while [ "$waited" -lt "$SSM_TIMEOUT" ]; do
    status=$(aws ssm describe-instance-information \
      --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
      --query 'InstanceInformationList[0].PingStatus' --output text)
    if [ "$status" = "Online" ]; then
      return 0
    fi
    log "SSM status is $status after ${waited}s"
    sleep "$POLL"
    waited=$((waited + POLL))
  done
  return 1
}

log "Waiting for SSM Online, up to ${SSM_TIMEOUT}s"
if ! wait_for_ssm; then
  # Lesson from M4. The SSM agent can start before the instance profile
  # works, and then it never registers. A reboot restarts the agent.
  log "Not Online after ${SSM_TIMEOUT}s, rebooting once"
  aws ec2 reboot-instances --instance-ids "$INSTANCE_ID"
  wait_for_ssm || fail "SSM still not Online after the reboot. Check the instance profile and the SSM endpoints"
fi
log "SSM Online"

# ---------- 4. Wait for K3s Ready ----------
# This check runs on the node as root through SSM Run Command.
# It prints READY when the node is Ready, FAILED when cloud-init (the user
# data script) reported an error, and WAITING while K3s is still installing.
# It has no double quotes, because it goes inside a JSON string below.
REMOTE_CHECK='if /usr/local/bin/k3s kubectl get node --no-headers 2>/dev/null | grep -qw Ready; then echo READY; elif cloud-init status | grep -q error; then echo FAILED; else echo WAITING; fi'

# Sends the check, waits for it to finish, and prints its one-word result.
# Any AWS error prints nothing, and the loop treats nothing as WAITING.
check_k3s() {
  local cmd_id
  cmd_id=$(aws ssm send-command \
    --instance-ids "$INSTANCE_ID" \
    --document-name AWS-RunShellScript \
    --parameters "{\"commands\":[\"$REMOTE_CHECK\"]}" \
    --query 'Command.CommandId' --output text) || return 0
  sleep 2
  aws ssm wait command-executed --command-id "$cmd_id" --instance-id "$INSTANCE_ID" 2>/dev/null || true
  aws ssm get-command-invocation \
    --command-id "$cmd_id" --instance-id "$INSTANCE_ID" \
    --query 'StandardOutputContent' --output text 2>/dev/null | tr -d '[:space:]' || true
}

log "Waiting for K3s Ready, up to ${READY_TIMEOUT}s"
waited=0
while true; do
  result=$(check_k3s)
  if [ "$result" = "READY" ]; then
    break
  fi
  if [ "$result" = "FAILED" ]; then
    fail "user data failed on the node. Read /var/log/cloud-init-output.log through SSM"
  fi
  if [ "$waited" -ge "$READY_TIMEOUT" ]; then
    fail "K3s not Ready after ${READY_TIMEOUT}s. Last check returned ${result:-nothing}"
  fi
  log "K3s check returned ${result:-nothing} after ${waited}s"
  sleep "$POLL"
  waited=$((waited + POLL))
done

# ---------- 5. Done ----------
ELAPSED=$(( $(date +%s) - START_TIME ))
log "K3s node $INSTANCE_ID is Ready"
log "Full rebuild took $((ELAPSED / 60))m $((ELAPSED % 60))s, including the time to type yes"
log "Connect with aws ssm start-session --target $INSTANCE_ID"
log "Run kubectl as sudo /usr/local/bin/k3s kubectl get nodes"
