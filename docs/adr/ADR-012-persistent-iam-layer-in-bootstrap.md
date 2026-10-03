# ADR-012: Persistent IAM layer in bootstrap

**Date:** 2026-10-03
**Status:** Accepted
**Deciders:** CJ
**Tags:** security, tooling, iam
**Amends:** ADR-005 (where the OIDC resources live)

## Context

The IAM module was called from `environments/dev`. It created the permission boundary, the GitHub OIDC provider, the CI role and its policy, and the EC2 SSM role and instance profile.

In M5 the dev stack is applied and destroyed every session to keep cost under $2 a month. I destroyed dev at M4 close. The OIDC provider and the CI role went with it.

On 3 Oct a PR failed at the first CI step. GitHub Actions could not assume the CI role because the role did not exist. CI needs the role to plan dev, and dev created the role. While dev is down, CI cannot run.

The permission boundary also denies `iam:CreateRole`, `iam:AttachRolePolicy` and `iam:PassRole` to bounded principals. The CI role is bounded. So CI could never create the IAM resources in dev anyway. Only `cj-admin` could, from my machine.

## Decision

I moved the whole `module "iam"` call from `environments/dev` to `bootstrap`. Bootstrap is never destroyed and is applied locally as `cj-admin`.

Bootstrap now owns the permission boundary, the OIDC provider, the CI role with its policy and attachment, the EC2 SSM role with its SSM policy attachment, and the instance profile. I added the EC2 Spot service-linked role to the same layer. It is also account-wide and only created once.

Dev no longer creates IAM. It reads the instance profile with `data.aws_iam_instance_profile.ec2_ssm`. If bootstrap has not been applied, the dev plan fails at that lookup. That is intended.

I kept `name_prefix = "platform10-dev"` so role, policy and profile names did not change. The CI workflows still assume the same role ARN.

Dev state was empty when I made the change, so nothing had to move between state files. I applied bootstrap from the feature branch before pushing, so the PR's CI run could prove the role works. This is the one exception to merge-then-apply. Bootstrap is the layer CI cannot create for itself.

## Alternatives considered

### Move only the CI identity

Move the OIDC provider, CI role and boundary, and leave the EC2 SSM role in dev. Rejected. The boundary denies `iam:CreateRole`, so CI still could not create the EC2 SSM role. Dev would keep IAM that only `cj-admin` can apply.

### Keep IAM in dev and stop destroying it

Rejected. A partial destroy needs `-target` or a split state. That is a bootstrap layer with extra steps.

### Separate IAM root module with remote state

Cleaner for a team. Rejected for now. It adds a third root module and a third apply step for one person. Bootstrap already has the right lifecycle.

## Consequences

### Positive

- CI works whether dev is up or down.
- Dev has no IAM, so CI never needs permission to create roles.
- The instance profile exists before any instance launches. This removes the cause of the M4 IAM propagation incident, where the profile and the instance were created in the same apply. I keep the SSM Online wait in the apply script as a safety net.
- Cost stays at $0. IAM has no charge.

### Negative

- Bootstrap uses local state and sits outside CI. Nothing warns me if it drifts. On the same day I found a lifecycle rule merged on 10 Aug that was never applied. I now run `terraform plan` in bootstrap before changing it.
- CI policy changes, including the M5 launch template and EventBridge additions, are applied from my machine, not by CI.
- The CI policy still lists IAM write actions that dev no longer needs. The boundary blocks them. I remove them in the k3s-cluster PR.

### Production contrast

A team would put this layer in its own repo or root module with remote state. It would run through CI with a separate, more privileged role and stricter review. A human still creates the first CI identity by hand. The bootstrap step does not go away. It gets smaller.

## Related

- ADR-005 OIDC federation. This ADR changes where its resources live.
- M4 build doc, IAM propagation incident.
