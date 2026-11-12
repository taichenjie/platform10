# CI Role Split Evidence

**Date:** 2026-11-12
**PR:** #27 (review #3 fixes)
**Roles:** platform10-ci-plan (read-only), platform10-ci-apply (write)

## What I tested

After the split, the apply role trusts one subject, `environment:production-apply`.
With an environment, GitHub puts the environment name in the OIDC `sub` claim
instead of the branch. So the trust policy cannot see which branch is asking.
The environment's deployment-branch rule (main only) is the only thing keeping
other branches out of the write role.

I ran three checks. One proves the PR plan uses the new read-only role. Two
prove that a branch other than main cannot get either role, and each one tests
a different layer.

## 1. PR plans run as the plan role

| Item | Value |
|---|---|
| Run | https://github.com/taichenjie/platform10/actions/runs/43175243653 |
| Result | Passed (fmt, validate, tflint, plan, Infracost, Checkov) |
| Assumed role ID in the log | `AROAW3YL6TXHM7FWCEDGC` |
| `aws iam get-role --role-name platform10-ci-plan` RoleId | `AROAW3YL6TXHM7FWCEDGC` |
| Old role `platform10-github-actions-ci` last used | 2026-10-22, before this PR |

I matched the role ID, not the role name. The run log prints only the ID, and
the ID cannot be reused by a recreated role.

## 2. Non-main dispatch is refused by the plan role

| Item | Value |
|---|---|
| Run | https://github.com/taichenjie/platform10/actions/runs/43176818370 |
| Command | `gh workflow run terraform-apply.yml --ref ci/role-split -f confirm=apply` |
| `sub` sent | `repo:taichenjie/platform10:ref:refs/heads/ci/role-split` |
| Failed step | Configure AWS credentials (plan role), after 2m44s of retries |
| Error | `Could not assume role with OIDC: Not authorized to perform sts:AssumeRoleWithWebIdentity` |
| Apply job | Skipped |

This test stops at the plan role. It would still pass with the environment rule
deleted, so it does not prove the apply role is protected. That is why test 3
exists.

## 3. Non-main branch is refused by the environment

| Item | Value |
|---|---|
| Run | https://github.com/taichenjie/platform10/actions/runs/43177632185 |
| Branch | `test/env-gate`, a throwaway branch deleted after the run |
| Probe | One job with `environment: production-apply` that tries to assume platform10-ci-apply. No plan job in front of it |
| Result | Failed in 3s. No step ran, so no OIDC token was requested |
| Error | `Branch "test/env-gate" is not allowed to deploy to production-apply due to environment protection rules.` |

Environment settings at the time of the test (`gh api .../environments/production-apply`).

| Setting | Value |
|---|---|
| `deployment_branch_policy` | `custom_branch_policies: true`, one policy, `main` (type branch) |
| `required_reviewers` | taichenjie |
| `can_admins_bypass` | true (accepted, sole maintainer; recorded in ADR-005) |

## Conclusion

A branch other than main cannot get either CI role. The plan role refuses it in
IAM. The apply role is reached only through production-apply, and the
environment refuses the branch before the job starts. PR plans run with the
read-only role.

## 4. Main dispatch plans, waits for approval, applies the saved plan

| Item | Value |
|---|---|
| Run | https://github.com/taichenjie/platform10/actions/runs/43181637874 |
| Commit | `89a36f0` on `main` (PR #27 merge) |
| plan job | Passed in 33s as platform10-ci-plan. Run summary showed `Plan: 38 to add, 0 to change, 0 to destroy.` |
| Gate | `production-apply waiting for review`. I read the plan in the summary, then approved |
| Verify step | `tfplan.binary: OK` |
| Apply | `Apply complete! Resources: 38 added, 0 changed, 0 destroyed.` |
| Clean-up | Destroyed locally (38), orphan audit passed, EBS volumes 0 |

This closes review #3 finding 3. The plan existed and was readable before I
approved, and the apply job applied that exact file. It also proves the apply
role holds every write the dev stack needs, on its first run.
