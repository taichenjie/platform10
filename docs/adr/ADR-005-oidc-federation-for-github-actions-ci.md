# ADR-005: OIDC federation for GitHub Actions CI

**Date:** 2026-08-27
**Status:** Accepted
**Deciders:** CJ
**Tags:** security, tooling

## Context

In our Github Actions workflow, we have Terraform plan and apply workflows that needed authentication to AWS.
The M2 CI pipeline authenticated to AWS using static IAM access keys
stored in GitHub Secrets. These keys belonged to the `cj-admin` IAM user
and had broad permissions. They worked, but they introduced a risk that
grew with every workflow run: the keys were long-lived, usable from any
IP or machine, and valid until manually rotated. A single leak (log spill,
compromised runner, malicious action dependency) would give an attacker
standing access to the AWS account with no expiry.

GitHub Actions supports OIDC federation, which replaces static keys with
short-lived STS credentials generated per workflow run. The credentials
expire in minutes and are bound to a specific repo, branch, and workflow
context. With OIDC federation, there is zero risk of static credentials being leaked. It provides a more secure authentication method.

## Decision

I replaced static IAM keys with OIDC federation. The implementation
lives in `modules/iam/oidc.tf` and consists of four resources: an OIDC
provider that registers GitHub's token service with AWS, an IAM role with
a trust policy pinning the `sub` claim to three allowed contexts, a
least-privilege permission policy, and a role-policy attachment.

The trust policy allows three sub claim values:
- `repo:taichenjie/platform10:ref:refs/heads/main` (push and dispatch)
- `repo:taichenjie/platform10:pull_request` (PR plan)
- `repo:taichenjie/platform10:environment:production-apply` (gated apply)

Both workflow files (`terraform-plan.yml` and `terraform-apply.yml`) were
updated to use `role-to-assume` with `id-token: write` permission. Static
keys were removed from GitHub Secrets after all three workflow paths were
verified green.

## Rationale

**OIDC over static keys.** Static keys require secret
management: rotation schedules, access audits, leak detection. OIDC
eliminates the secret entirely. There is no key to rotate, leak, or
manage. We use federation to obtain short lived credentials that are more secure.

**Least-privilege custom policy over managed policy.** I wrote a custom
permission policy listing exactly what Terraform needs for the current
32-resource stack (EC2, VPC, IAM, S3 state bucket, SSM, STS). The
alternative was attaching `PowerUserAccess` and relying on the permission
boundary as the ceiling. I chose the custom policy because each future
permission expansion (Q3 K3s resources) becomes a tracked, reviewable
change rather than silent scope creep. Also to practice the principle of least privilege.

**Three sub claims over one.** A single `refs/heads/main` claim would
block the PR plan workflow (which produces a `pull_request` sub claim)
and the gated apply workflow (which produces an `environment:production-apply`
sub claim). The three-entry list is the minimum set that covers all
legitimate workflow paths.

## Trade-offs accepted

**The permission policy must be updated when new resource types are added.**
The custom policy lists specific actions. When Q3 adds K3s-related
resources (ELB, autoscaling, EKS/EC2 for nodes), those actions must be
added to the policy or CI will fail with `AccessDeniedException`. This is
a deliberate maintenance cost that forces every permission expansion to be
reviewed.

**The permission policy was derived iteratively, not upfront.** The first
version was missing `ssm:GetParameter` (needed by a data source in the
compute module for AMI lookup). This only surfaced when the workflow ran
in CI because the local environment uses broader `cj-admin` permissions.
The lesson: least-privilege policies cannot be written accurately in one
pass. CI needs to be run iteratively to ensure an accurately written permission policy.

**The environment sub claim was discovered through failure.** The initial
trust policy did not include `environment:production-apply` because most
OIDC setup guides only show ref-based claims. The apply workflow failed
on the first attempt. GitHub Actions overrides the ref-based sub claim
with an environment-based claim when a job uses a named environment. This
is not prominently documented.

**Local and CI now use different identities.** Local runs authenticate as
`cj-admin` with broad permissions. CI authenticates as
`platform10-github-actions-ci` with scoped permissions defined in the
permission policy. A plan that passes locally can fail in CI for
permission reasons. This is acceptable because CI runs the same code
against the same state but with the actual scoped credentials that
production would use, making it the real validation of whether the
permission policy is correct. Local is a convenience for fast feedback,
not a guarantee.

## Production path

In a production system:

1. The OIDC provider would be shared across multiple repositories, each
   with its own role and trust policy pinned to that repo's sub claims.

2. The permission policy would be generated from IAM Access Analyzer
   after the workload has been running, using CloudTrail logs of actual
   API calls rather than manual enumeration. I am not using Access
   Analyzer here because it requires CloudTrail to be enabled and
   logging API calls over a sustained period. This project runs under
   apply/destroy discipline with no long-running workload, so there is
   no meaningful trail to analyze. The manual iterative approach
   (run CI, read the AccessDeniedException, add the missing permission)
   achieves the same result at this scale.

3. The trust policy would pin sub claims to specific workflow filenames
   (`job_workflow_ref`) in addition to repo and branch, preventing a
   renamed or modified workflow from assuming the role without review.

4. A break-glass path would exist: a separate IAM role with broader
   permissions, assumable only by a named set of humans via MFA, for
   incident response when the OIDC path is broken or insufficient.

5. Static keys for local development would be replaced with
   `aws sso login` or similar federated access, eliminating long-lived
   keys from developer machines as well.

## Links

- OIDC Terraform code: `infra/terraform/modules/iam/oidc.tf`
- OIDC role output: `infra/terraform/modules/iam/outputs.tf`
- Plan workflow: `.github/workflows/terraform-plan.yml`
- Apply workflow: `.github/workflows/terraform-apply.yml`
- Negative test evidence: `docs/evidence/oidc-negative-test.md`
- Negative test workflow run: https://github.com/taichenjie/platform10/actions/runs/32851611045
- OIDC PR: https://github.com/taichenjie/platform10/pull/4
- AWS OIDC documentation: https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles_providers_create_oidc.html
- GitHub OIDC documentation: https://docs.github.com/en/actions/deployment/security-hardening-your-deployments/configuring-openid-connect-in-amazon-web-services
