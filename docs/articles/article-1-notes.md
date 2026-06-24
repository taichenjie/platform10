# Article 1 — Raw Notes
# "Frugal Cloud Architecture: Replacing the $32/Month NAT Gateway"
# Build notes, not the article. Source material for writing it later.

## Cost figures

- Managed NAT Gateway: $0.045/hr + $0.045/GB. About $32/mo (US East) before
  any traffic. ap-southeast-1 is higher: $0.059/hr, about $43/mo.
- Self-managed NAT instance (t4g.nano): $3.87/mo compute + $0.77/mo EBS.
- Infracost worst-case 24/7 for the full Q1 network: $52.09/mo. Of that,
  the 5 interface endpoints are ~$47. The NAT compute is the small part.
- Real spend with apply/destroy discipline: ~$0.02 for a 20-25 minute cycle.

## How the self-managed NAT works

Three settings make a plain EC2 instance act as a NAT:

1. source_dest_check = false on the instance.
   AWS drops any packet whose source or destination IP is not the instance's
   own IP, unless this check is off. A NAT forwards packets belonging to other
   hosts, so the check must be false. This is the setting that makes it a NAT.

2. Kernel IP forwarding: net.ipv4.ip_forward = 1, set via a drop-in file in
   /etc/sysctl.d so it survives reboot.

3. iptables MASQUERADE rule, scoped to the VPC CIDR, on the primary interface.
   Rewrites the source IP of outbound VPC traffic to the NAT's own IP.

## The user_data script (modules/vpc/files/nat-userdata.sh)

- set -euo pipefail so any failed step stops the script.
- Logs to /var/log/user-data.log for debugging.
- Detects the primary network interface from the default route instead of
  hardcoding ens5.
- Read into Terraform with templatefile() so the VPC CIDR is substituted in,
  not hardcoded.

## Routing

- Private route table: 0.0.0.0/0 -> NAT instance ENI (separate aws_route).
- Public route table: 0.0.0.0/0 -> IGW (inline route).
- Outbound path: private subnet -> private route table -> NAT ENI ->
  NAT kernel MASQUERADE -> public route table -> IGW (rewrites to EIP) ->
  internet.
- Inbound return: handled by the implicit local route plus iptables
  connection tracking. No explicit inbound route needed.

## First apply/verify/destroy cycle (Day 16)

Apply: 31 resources in about 3 minutes.

Verified inside the NAT over SSM Session Manager (no SSH, no bastion):

- cloud-init status: done
- user_data log last line: "NAT setup complete at Sun Jun 21 05:06:40 UTC 2026"
- net.ipv4.ip_forward = 1
- iptables MASQUERADE rule present. 238 packets / 18819 bytes already
  forwarded during cloud-init's own dnf calls.
- curl ifconfig.me returned 3.1.33.30, which is the EIP. Confirms outbound
  works and exits via the IGW.
- SSM endpoint /ping: HTTP 200 in 0.026s. 26ms means the request went to the
  interface endpoint inside the VPC via private DNS, not the public internet.

The SSM session connecting at all confirms the IAM role, permission boundary,
instance profile, SSM endpoints, endpoint SG, and agent registration are all
correct at once.

Destroy: 31 destroyed, clean. Post-destroy audit with 4 AWS CLI checks
filtered by Project=platform10 tag returned zero orphans. EIP and NAT instance
both confirmed gone.

## The trade-off

A single NAT instance is a single point of failure in one AZ. If it dies,
all private subnet egress dies until it is rebuilt.

Production options (from ADR-001):
1. Two NAT instances, one per AZ, each in an ASG of size 1 with a launch
   template.
2. Switch to fck-nat: maintained AMI, HA mode, Terraform module.
3. Accept the cost and use Managed NAT Gateway.

fck-nat is the correct production choice and was evaluated. The self-managed
instance was chosen here to show understanding of the underlying mechanics.

## Links to add when writing the article

- ADR-001 (NAT trade-off)
- ADR-002 (single-AZ endpoint placement)
- docs/cost/m1-baseline.txt (Infracost report)
- modules/vpc/files/nat-userdata.sh (the script)
- git history (build narrative)
- M1-close real invoice (once captured)
