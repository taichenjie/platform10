# ADR-003: S3 remote state backend with native locking

**Date:** 2026-06-29
**Status:** Accepted
**Deciders:** CJ
**Tags:** tooling, reliability

## Context

Until now, Terraform state for the dev environment lived in a local file
on my WSL2 disk. That has three problems:

- Single copy. If the disk dies or the file corrupts, Terraform loses
  track of everything it built. The resources stay in AWS but become
  orphans I have to find and delete by hand.
- No locking. Two applies at once can write the state file simultaneously and
  corrupt it.
- Not shareable. GitHub actions pipeline in the future cannot read Terraform state file
stored locally.

The state needs to move to shared, durable, versioned storage with a
locking mechanism.

## Decision

I moved Terraform state to an S3 bucket and enabled S3-native locking
with `use_lockfile = true`.

The bucket lives in a separate `infra/terraform/bootstrap/` config with
its own local state, applied once. The dev environment points at this
bucket via a `backend "s3"` block.

I did not use a DynamoDB lock table.

## Rationale

**Why a separate bootstrap config, not in the dev environment.**
The dev environment gets 'terraform destroy' run on it constantly.
If the state bucket lived inside the dev
config, every destroy would try to delete the bucket holding the state
file mid-operation. Hence, I put the S3 bucket in a separate config.
'terraform destroy' only acts on resources tracked in the state of the directory it runs from,
so the two configs are fully isolated, meaning my S3 bucket will remain available after
'terraform destroy' in the dev environment.

**Why S3-native locking, not DynamoDB.**
The original AWS pattern used a DynamoDB table for state locking because
S3 lacked the consistency guarantees to do it alone. Since Terraform
1.10, S3 supports native locking via conditional writes, Terraform
writes a `.tflock` object to the bucket and S3 rejects a second write if
it already exists. I am on Terraform 1.15.5, so DynamoDB is unnecessary.
The `dynamodb_table` backend argument is now deprecated.

I initially created a DynamoDB table out of habit from older guides,
saw Terraform's deprecation warning on `dynamodb_table`, and removed the
table. S3-native locking is one fewer resource to manage, fewer IAM
permissions, and no separate billing line.

## Trade-offs accepted

**Bucket protected only by prevent_destroy and Block Public Access.**
The bucket has `prevent_destroy = true` so Terraform refuses to delete
it, versioning so a bad state write can be rolled back, and Block Public
Access so it is never publicly readable. It does not yet have a bucket
policy restricting which principals can access it, or MFA delete. For a
solo project this is acceptable; in production I would add both.

**Bootstrap uses local state.**
The bootstrap config itself stores its state locally. There is no
second backend to hold the backend's own state. This is the standard
bootstrap pattern. The bootstrap state rarely changes (the bucket is
created once), so the risk of losing it is low, and the bucket can be
re-imported if needed.

## Production path

If this were a production system:

1. **Bucket policy** restricting state bucket access to specific IAM
   roles, plus MFA delete on the bucket.

2. **Separate state per environment** under different keys in the same
   bucket (already structured this way: `environments/dev/terraform.tfstate`).

3. **Bootstrap state in version control or a separate hardened backend**
   rather than purely local, so the backend's own state is also durable.

## Links

- Bootstrap config: `infra/terraform/bootstrap/`
- Dev backend block: `infra/terraform/environments/dev/versions.tf`
- Terraform S3 backend docs: https://developer.hashicorp.com/terraform/language/backend/s3
