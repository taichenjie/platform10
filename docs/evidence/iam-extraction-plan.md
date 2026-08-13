# IAM Module Extraction: Moved Block Evidence

**Date:** August 2026
**Branch:** feat/extract-iam-module
**PR:** #2
**Test method:** Applied 32 resources from main (old inline IAM addresses), switched to extraction branch, planned against live state.

## Moved block results

```
# aws_iam_instance_profile.ec2_ssm has moved to module.iam.aws_iam_instance_profile.ec2_ssm
  resource "aws_iam_instance_profile" "ec2_ssm" {
      id          = "platform10-dev-ec2-ssm-profile"
      name        = "platform10-dev-ec2-ssm-profile"
      # (7 unchanged attributes hidden)
  }

# aws_iam_policy.permission_boundary has moved to module.iam.aws_iam_policy.permission_boundary
  resource "aws_iam_policy" "permission_boundary" {
      id               = "arn:aws:iam::471934606798:policy/platform10-dev-permission-boundary"
      name             = "platform10-dev-permission-boundary"
      # (8 unchanged attributes hidden)
  }

# aws_iam_role.ec2_ssm has moved to module.iam.aws_iam_role.ec2_ssm
  resource "aws_iam_role" "ec2_ssm" {
      id                    = "platform10-dev-ec2-ssm-role"
      name                  = "platform10-dev-ec2-ssm-role"
      # (12 unchanged attributes hidden)
  }

# aws_iam_role_policy_attachment.ec2_ssm_core has moved to module.iam.aws_iam_role_policy_attachment.ec2_ssm_core
  resource "aws_iam_role_policy_attachment" "ec2_ssm_core" {
      id         = "platform10-dev-ec2-ssm-role/arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
      # (2 unchanged attributes hidden)
  }
```

## Plan summary

```
Plan: 0 to add, 0 to change, 0 to destroy.
```

## What this proves

- Four IAM resources changed Terraform address from root module to module.iam.
- Every resource shows "has moved to" with unchanged attributes.
- No resource was destroyed, created, or modified in AWS.
- State was updated in place. Zero downtime.
