# ADR-001: Self-managed NAT instance over Managed NAT Gateway

**Date:** 2026-06-17
**Status:** Accepted
**Deciders:** CJ
**Tags:** networking, cost, reliability

## Context

Private subnets in this VPC need outbound internet access to fetch package
updates, reach AWS APIs not covered by a VPC endpoint, and later let the RPC
node reach external peers.

To do this, we need Network Address Translation (NAT) to translate private
IPs of my private subnets into public IPs that can reach Internet Gateway
(IGW).

The project has a hard sub-$10/mo budget. There is no free tier and no
promotional credits. Every cost decision needs to be deliberate and
considered with this budget in mind.

ap-southeast-1 pricing applies throughout.

## Decision

I chose to run a self-managed NAT instance on a t4g.nano running Amazon
Linux 2023. IP forwarding and an iptables MASQUERADE rule are installed
via cloud-init user data on first boot. The instance lives in the public
AZ1 subnet at a fixed private IP (10.0.0.10) with a stable Elastic IP for
its public address.

## Rationale

I considered three alternatives.

**Managed NAT Gateway.** Rejected on cost. At ap-southeast-1 rates, a
single NAT Gateway runs approximately $32/mo before any data is processed,
plus $0.045/GB data processing on top. That alone breaks the sub-$10
monthly budget for the entire project, before EC2, EBS, or anything else
is added.

**fck-nat.** Rejected, but only after serious evaluation. fck-nat is an
actively-maintained open-source NAT AMI built on Amazon Linux 2023, with
ARM support, security patching, and a published Terraform module. For a
production deployment with no special learning objective, it is the
correct choice. I rejected it here because the point of this project is
to demonstrate that I understand how a NAT instance actually works — IP
forwarding, source/destination check, MASQUERADE, route propagation. If
I deploy fck-nat, those mechanics live inside someone else's AMI and the
repo no longer shows that I know them. The user_data script in this
module is the demonstration and proof of my learning. For a real
production system, I would use fck-nat.

**Official AWS NAT instance AMI.** Rejected outright. The AMI was last
updated in 2018, runs Amazon Linux 1 (EOL), and has no ARM support. I
will not put an unpatched 8-year-old image on my internet gateway.

## Trade-offs accepted

**Single point of failure.** We only have one NAT instance in one AZ. If
the instance fails, every private subnet loses internet egress until I
rebuild or replace it. The managed NAT Gateway gives high availability
inside a single AZ for free; I have given that up.

**Manual patching.** I own kernel and OS updates for the NAT instance.
AWS no longer patches it for me.

**No autoscaling.** Bandwidth is capped at whatever the t4g.nano supports
(5 Gbps burst), which is far above what this project needs but is still
a fixed ceiling. The managed NAT Gateway, on the other hand, scales
bandwidth automatically.

**No AWS-provided monitoring.** I do not get the CloudWatch metrics that
ship with a managed NAT Gateway. If I want to know when the NAT is
unhealthy, I have to instrument that myself.

## Production path

If this were a production system serving real traffic, I would do one of
these, in order of preference:

1. **Two NAT instances, one per AZ.** Each private subnet's route table
   would point to the NAT instance in its own AZ. Combined with an
   Auto Scaling Group of size 1 per AZ and a launch template, a failed
   NAT would be replaced automatically. This removes the SPOF without
   moving to a managed service.

2. **Switch to fck-nat.** Its high-availability mode handles the
   per-AZ wiring and instance replacement out of the box, and avoids the
   per-OS-patch maintenance burden.

3. **Accept the cost and use Managed NAT Gateway.** If the workload
   justifies $32+/mo per AZ for fully managed HA and AWS-provided
   monitoring, this is the correct production answer.

I will not run a single NAT instance in production. That choice is
acceptable here because the budget is the hard constraint and the
feature of my project, and I am the only person affected if the NAT
goes down.

## Links

- Implementation: `infra/terraform/modules/vpc/main.tf` (aws_instance.nat block)
- User data script: `infra/terraform/modules/vpc/files/nat-userdata.sh`
- Related blog post (planned): "Frugal Cloud Architecture: Replacing the $32/Month NAT Gateway"
- fck-nat: https://github.com/AndrewGuenther/fck-nat
