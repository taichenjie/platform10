# ADR-012: Persistent IAM layer in bootstrap

**Date:** 2026-10-03
**Status:** Accepted
**Amended:** 2026-10-10 (bootstrap state moved to S3, CI denied bootstrap state)
**Deciders:** CJ
**Tags:** security, tooling, iam, state
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

Bootstrap state started on local disk. On 10 Oct I moved it to the S3 backend and denied CI access to it. See the amendment at the end.

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

- Bootstrap sits outside CI. Nothing warns me if it drifts. On the same day I found a lifecycle rule merged on 10 Aug that was never applied. I now run `terraform plan` in bootstrap before changing it. Its state has been in S3 since 10 Oct (see the amendment below).
- CI policy changes, including the M5 launch template and EventBridge additions, are applied from my machine, not by CI.
- The CI policy still lists IAM write actions that dev no longer needs. The boundary blocks them. I planned to remove them in the k3s-cluster PR, but that PR merged without the change. Removing them is a separate follow-up PR.

### Production contrast

A team would put this layer in its own repo or root module with remote state. It would run through CI with a separate, more privileged role and stricter review. A human still creates the first CI identity by hand. The bootstrap step does not go away. It gets smaller.

## Amendment, 10 Oct 2026: bootstrap state in S3

### Why now

Bootstrap kept its state on local disk from M1. That was fine while it held one bucket. On 3 Oct it took over every IAM resource CI depends on, and the state file stayed on my WSL disk.

Local state had three concrete risks. If the WSL disk was lost, Terraform would forget it owns 19 resources, and I would have to import each one by hand. There was no version history, so a bad write could not be undone. There was no lock, so nothing stopped two applies from running at once.

I deferred the move on 3 Oct because the IAM move had to land quickly to unblock CI. Changing the backend in the same PR would have mixed a modify with a refactor. A project audit on 9 Oct flagged the deferral, and I did it the next day.

### Decision

Bootstrap state now lives at `bootstrap/terraform.tfstate` in the existing state bucket, with `use_lockfile` and encryption. This is the same convention as dev (ADR-003).

Bootstrap creates that bucket, so it stores its state in a bucket it manages. This is safe for three reasons. The bucket existed before the backend pointed at it. `prevent_destroy = true` makes Terraform refuse any plan that deletes it. Versioning keeps every previous state.

CI must not touch bootstrap state. That state describes the CI role and its policy. If CI could overwrite it, my next local bootstrap apply would act on a ledger CI had changed. If CI could delete it, Terraform would forget it owns the IAM layer.

CI previously had Get, Put and Delete on every object in the bucket. I narrowed this to `environments/*`, which covers each environment's state file and its `.tflock`. I added an explicit Deny on `bootstrap/*`, so a future change that widens the Allow still cannot reach bootstrap state. `ListBucket` stays bucket-wide because the backend lists keys during `init`, and key names are not sensitive.

### Alternatives considered

#### A separate bucket for bootstrap state

This gives stronger isolation. Rejected. Something still has to create that bucket, so the chicken-and-egg moves up one level. It also adds a second bucket to secure and pay for. A key prefix with an explicit Deny gives CI the same separation.

#### Keep local state and take backups

Rejected. Backups fix disk loss but not locking. They also depend on me remembering to take them after every apply.

#### Put the Deny in the bucket policy instead of the CI policy

A bucket policy Deny is stronger in one way. CI cannot edit a bucket policy, but it might be able to edit its own identity policy. I kept the Deny in the CI policy for now, because every CI permission already lives and gets reviewed there. Whether the permission boundary stops CI from editing its own policy is open. The follow-up PR that narrows `IAMManagement` checks this with the policy simulator. If the boundary does not stop it, the Deny moves to a bucket policy.

#### Separate AWS account for CI identity and state

This is the team answer. Rejected for a single-person, single-account project on a sub-$10 budget. See Production contrast.

### Order of operations

I narrowed CI's access first, in its own PR, and migrated second. In the other order, there is a window where bootstrap state sits in the bucket and CI's old bucket-wide access covers it.

1. Confirmed bootstrap `plan` showed no changes, so the migration would not mix with a pending change.
2. Applied the narrowed CI policy as v2. v1 is kept for rollback with `aws iam set-default-policy-version`.
3. Checked v2 with the IAM policy simulator. Get, Put and Delete are allowed on `environments/dev` state and `.tflock`. All three return `explicitDeny` on `bootstrap/terraform.tfstate`.
4. Re-ran the latest CI plan workflow under v2. It passed.
5. Added the `backend "s3"` block and ran `terraform init -migrate-state`. The destination key was empty.
6. Verified 19 resources in remote state, no changes on `plan`, and no lock left behind.
7. Deleted the local state files. I kept one offline copy until this PR merges.

### Rebuild in a new account

Comment out the `backend "s3"` block. Run `terraform init` and `terraform apply` with local state. Restore the block and run `terraform init -migrate-state`.

### Consequences

Bootstrap state now has locking, version history and encryption, and does not depend on one disk.

Bootstrap still sits outside CI. The state move does not add drift detection. I still run `terraform plan` in bootstrap before changing it.

Bootstrap changes still reach AWS before review. The PR records an apply that already happened.

## Related

- ADR-003 S3 remote state backend. Bootstrap now uses the same backend convention.
- ADR-005 OIDC federation. This ADR changes where its resources live.
- M4 build doc, IAM propagation incident.
