# OIDC Negative Test Evidence

**Date:** 2026-08-25
**Branch:** test-negative-oidc
**Workflow:** oidc-negative-test.yml
**Run URL:** https://github.com/taichenjie/platform10/actions/runs/32851611045/job/97813621970

## What was tested

A workflow on an unauthorized branch (test-negative-oidc) attempted to assume
the OIDC role platform10-github-actions-ci via sts:AssumeRoleWithWebIdentity.

The trust policy only allows three sub claim contexts:
- repo:taichenjie/platform10:ref:refs/heads/main
- repo:taichenjie/platform10:pull_request
- repo:taichenjie/platform10:environment:production-apply

The branch produced sub claim repo:taichenjie/platform10:ref:refs/heads/test-negative-oidc,
which is not in the allowed list.

## Result

STS rejected the token after 11 retry attempts:
"Could not assume role with OIDC: Not authorized to perform sts:AssumeRoleWithWebIdentity"

The "This step should never run" step did not execute.

## Conclusion

The trust policy correctly rejects tokens from unauthorized workflow contexts.
