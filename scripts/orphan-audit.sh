#!/usr/bin/env bash
# orphan-audit.sh checks that nothing from the dev stack is left in AWS.
#
# Run it after every destroy. dev-destroy.sh calls it automatically.
# Each check counts one resource type. Anything above zero is an orphan,
# which either costs money or clashes with the next apply.
#
# It exits 0 when every count is zero, and 1 when anything is found.
# Bootstrap resources (state bucket, IAM, Spot role) are not checked,
# because they are meant to stay.

# -e : exit immediately when any command fails
# -u : treat undefined variables as errors
# -o pipefail : fail a pipeline if any command in it fails
set -euo pipefail

export AWS_REGION="ap-southeast-1"
FOUND=0

log() { echo "$(date -u +%FT%TZ) $*"; }

# Runs one AWS count query and records the result.
# The first argument is a label, the rest is the AWS command.
check() {
  local label=$1 count
  shift
  count=$("$@" --output text)
  if [ "$count" = "0" ]; then
    log "OK     no $label"
  else
    log "FOUND  $count $label"
    FOUND=$((FOUND + count))
  fi
}

log "Orphan audit in $AWS_REGION"

# Billed by the hour.
check "instances (pending, running, stopping or stopped)" \
  aws ec2 describe-instances \
  --filters "Name=instance-state-name,Values=pending,running,stopping,stopped" \
  --query 'length(Reservations[].Instances[])'

check "EBS volumes" \
  aws ec2 describe-volumes --query 'length(Volumes)'

check "Elastic IPs" \
  aws ec2 describe-addresses --query 'length(Addresses)'

check "VPC endpoints" \
  aws ec2 describe-vpc-endpoints \
  --query "length(VpcEndpoints[?State!='deleted'])"

check "NAT gateways" \
  aws ec2 describe-nat-gateways \
  --filter "Name=state,Values=pending,available" \
  --query 'length(NatGateways)'

# Can launch new instances on their own.
check "open or active Spot requests" \
  aws ec2 describe-spot-instance-requests \
  --filters "Name=state,Values=open,active" \
  --query 'length(SpotInstanceRequests)'

# Free, but they clash with the next apply.
check "platform10 VPCs" \
  aws ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=platform10*" \
  --query 'length(Vpcs)'

check "platform10 launch templates" \
  aws ec2 describe-launch-templates \
  --filters "Name=launch-template-name,Values=platform10*" \
  --query 'length(LaunchTemplates)'

check "platform10 EventBridge rules" \
  aws events list-rules --name-prefix platform10 \
  --query 'length(Rules)'

check "platform10 event log groups" \
  aws logs describe-log-groups --log-group-name-prefix /aws/events/platform10 \
  --query 'length(logGroups)'

if [ "$FOUND" -ne 0 ]; then
  log "Audit FAILED, $FOUND orphaned resources. Delete them or run terraform destroy again"
  exit 1
fi
log "Audit passed, nothing left"
