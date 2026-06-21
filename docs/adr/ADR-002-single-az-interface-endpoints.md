# ADR-002: Single-AZ placement for interface VPC endpoints

**Date:** 2026-06-18
**Status:** Accepted
**Deciders:** CJ
**Tags:** networking, cost

## Context

The Q1 design requires interface VPC endpoints for SSM (3 endpoints:
ssm, ssmmessages, ec2messages) and ECR (2 endpoints: ecr.api, ecr.dkr)
so that private subnet workloads can reach those AWS APIs without
going through the NAT instance and out to the public internet.

Interface endpoints are billed per AZ per hour. At ap-southeast-1 rates:
- approximately $0.013 per endpoint per AZ per hour
- $0.01/GB data processing

For 5 interface endpoints:
- One AZ: 5 × 730h × $0.013 = ~$47/mo if running 24/7
- Both AZs: 5 × 2 × 730h × $0.013 = ~$95/mo if running 24/7

This shows that 24/7 runtime breaks the sub-$10/mo budget. The
apply/destroy discipline (network exists only during build sessions)
is what keeps the actual invoice low. The choice to make here is whether
to place my interface endpoints in one AZ or two AZs, which will be
covered below.

## Decision

I chose to place all 5 interface VPC endpoints (3 SSM + 2 ECR) in
a single AZ — private-az1 only, rather than across both AZs.
The S3 gateway endpoint is unaffected by this decision because
gateway endpoints are not AZ-scoped.

## Rationale

I considered three alternatives.

**Both AZs (HA placement).** Rejected for two reasons. First, it
doubles the cost (~$95/mo vs ~$47/mo at 24/7). Second, the NAT
instance is already single-AZ in AZ1 (per ADR-001). If AZ1 fails,
the NAT is gone, so endpoints in AZ2 would have no working NAT to
serve as fallback for any non-endpoint traffic. Paying for two-AZ
endpoints on top of a single-AZ NAT is paying twice for the same
failure mode.

**Skip interface endpoints entirely (route SSM/ECR through NAT).**
Rejected. I want VPC endpoints for S3/SSM/ECR as a explicit security 
deliverable, with the rationale of keeping internal
AWS API traffic off the public internet. Going through the NAT
exposes those API calls to the public path, which removes the
data-exfiltration-path-closure property the endpoints exist to
provide.

**Single-AZ placement (chosen).** Matches the rest of the single-AZ
Q1 design, halves the cost of the endpoint set, and provides the
same security property as two-AZ placement. The only functional
difference is cross-AZ data charges for any private-az2 workload
that calls these APIs, which is negligible for SSM/ECR traffic
volumes.

## Trade-offs accepted

**Cross-AZ traffic for private-az2 workloads.** Anything running in
private-az2 that calls SSM or ECR resolves the endpoint DNS to the
ENI in private-az1. AWS charges $0.01/GB for cross-AZ data transfer,
which is negligible for SSM/ECR's low traffic volumes, but still exists.

**Single point of failure (per AZ).** If private-az1 is down,
every workload in either AZ loses SSM access and ECR access. This
matches the NAT instance's existing AZ1 dependency, so it does not
add a new failure mode.

**Cost still significant.** Even single-AZ, 5 interface endpoints
cost ~$47/mo at 24/7 — well above the sub-$10/mo budget. The
apply/destroy discipline (build only exists during work sessions)
is what keeps the actual monthly invoice low.

## Production path

If this were a production system serving real traffic, I would do
the following, in order:

1. **Two NAT instances per AZ first.** Endpoint HA without NAT HA
   does not buy anything (see ADR-001 production path). The two
   changes go together.

2. **Two-AZ endpoint placement.** Once the NAT is HA, place each
   interface endpoint set in both AZs. Cost approximately doubles
   to ~$95/mo for the endpoint set, which production budgets
   accept as the cost of removing the AZ-level dependency.

3. **VPC endpoint policies.** Add resource policies to the endpoints
   to constrain which IAM principals and accounts can use them. For
   Q1, the implicit "anything in the VPC that can reach the endpoint"
   is acceptable. In production I would scope this tightly.

## Links

- Implementation: `infra/terraform/modules/vpc/main.tf` (aws_vpc_endpoint blocks for ssm_family and ecr)
- Related: ADR-001 (NAT instance single-AZ trade-off — same shape of decision)
- Verified pricing source: `docs/cost/m1-baseline.txt` (Infracost report, run against the Q1 plan)
- AWS pricing: https://aws.amazon.com/privatelink/pricing/
