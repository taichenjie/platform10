# ADR-004: Moved-block refactor for module extraction

**Date:** 2026-08-13
**Status:** Accepted
**Deciders:** CJ
**Tags:** tooling, reliability

## Context

The M1 build placed all IAM resources inline in `environments/dev/iam.tf`
and all compute resources (NAT instance, SG, EIP) inside the VPC module
at `modules/vpc/main.tf`. This worked for a single environment, but
production Terraform codebases separate concerns into focused,
independently versioned modules. Extracting early enforces the same
discipline that multi-environment, multi-team organizations rely on:
each module owns its own lifecycle, inputs, and outputs.

Extracting resources into their own modules changes their Terraform
address. For example, `aws_iam_role.ec2_ssm` in the root module becomes
`module.iam.aws_iam_role.ec2_ssm`. Terraform tracks resources by address
in state. Without proper extraction, Terraform reads an address change as
"delete the old resource, create a new one," which causes production
outage if critical infrastructure is destroyed.

## Decision

I used Terraform `moved` blocks to map old addresses to new ones.
Terraform updates the state pointer instead of destroying and recreating.
The plan shows 0 to destroy.

The extraction was done in two separate PRs:

1. IAM extraction (PR #2): four resources moved from root module to
   `module.iam`, four moved blocks.
2. Compute extraction (PR #3): six resources moved from `module.vpc` to
   `module.compute`, six moved blocks.

Each PR was verified against live infrastructure before merging.

## Rationale

`moved` blocks are the standard declarative way to refactor Terraform.
They live in code, show up in PR diffs, and produce a reviewable plan
before anything changes. The imperative alternative (`terraform state mv`)
modifies state outside version control and is only used for emergencies.
Destroy-and-recreate is not acceptable for any resource with persistent
state or downstream dependencies.

## Trade-offs accepted

**Resource attributes must be identical before and after the move.** During
the IAM extraction, I changed two `aws_iam_policy` description strings
while moving the resources. The description field is immutable in AWS, so
changing it forced a destroy and recreate, which defeated the moved block.
Fix: revert descriptions to exact originals, confirm zero destroys, then
change attributes in a separate follow-up commit.

**Moved blocks only prove correct against live state.** Planning against
empty state always shows "N to add" whether moved blocks are correct or
not. The only valid test is: apply the old code, switch to the new code,
and plan against live state. The plan must show "has moved to" lines and
zero destroys.

**Moved blocks must stay in code until state has migrated.** Deleting a
moved block before the migrating apply removes the mapping. Terraform
falls back to destroy and recreate. Safe to remove in a follow-up commit
after the apply completes.

## Incidents during execution

**NAT drift discovery.** During the compute extraction live test, the plan
tried to force-replace the NAT instance. The cause was
`associate_public_ip_address` reading back as `true` after EIP attachment,
even though the code said `false`. This was hidden since M1 and unrelated
to the extraction. Fix: remove the argument entirely, since
`map_public_ip_on_launch = false` on the subnet already prevents
auto-assignment. Full writeup deferred to the blog post.

**Checkov skip ID mismatch.** Inline skip IDs from the plan-JSON parser
did not match the HCL-source parser range. Lesson: always verify skip IDs
against the active parser, and place skips on the `data` block where
Checkov raises the finding.

## Production path

In a production system with multiple environments and teams:

1. Moved blocks would be used for every module extraction or resource
   rename. `terraform state mv` would only be used for emergencies where
   the code cannot be changed first.

2. Each extraction would be a separate PR with at least one reviewer. The
   plan output showing "has moved to" lines and zero destroys would be
   required evidence before merge.

3. CI would run the plan against a staging environment's live state before
   the production apply, catching address mismatches and drift early.

## Links

- IAM extraction PR: https://github.com/taichenjie/platform10/pull/2
- Compute extraction PR: https://github.com/taichenjie/platform10/pull/3
- IAM module: `infra/terraform/modules/iam/`
- Compute module: `infra/terraform/modules/compute/`
- VPC module (resources removed): `infra/terraform/modules/vpc/main.tf`
- Moved blocks (IAM): `infra/terraform/environments/dev/iam.tf`
- Moved blocks (compute): `infra/terraform/environments/dev/compute-moved.tf`
- NAT drift fix: removal of `associate_public_ip_address` in compute extraction PR
- Related blog post (planned): "State Locking and Drift Wars: Refactoring Production Terraform Without Destructive Changes"
