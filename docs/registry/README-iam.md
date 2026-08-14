# terraform-aws-platform10-iam

Terraform module for Platform 10 IAM resources. Creates a permission boundary policy that caps all non-root principals, an EC2 SSM role bounded by that boundary, and an instance profile for EC2 attachment.

Designed for the Platform 10 project. The permission boundary blocks IAM privilege escalation, boundary tampering, and destructive account/org/KMS operations.

## Usage

```hcl
module "iam" {
  source = "taichenjie/platform10-iam/aws"

  name_prefix = "platform10-dev"
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| name_prefix | Prefix for all IAM resource names (e.g. platform10-dev) | string | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| permission_boundary_arn | ARN of the permission boundary policy |
| ec2_ssm_instance_profile_name | Name of the EC2 SSM instance profile |
| ec2_ssm_role_name | Name of the EC2 SSM role |

## Requirements

| Name | Version |
|------|---------|
| terraform | ~> 1.15.5 |
| aws | >= 6.0 |

## Permission boundary design

The boundary uses an Allow * baseline as a ceiling, not a grant. It gives no principal any permission on its own. Explicit Deny statements block:

- IAM privilege escalation (CreatePolicy, AttachRolePolicy, PassRole, etc.)
- Boundary tampering (DeleteRolePermissionsBoundary, PutRolePermissionsBoundary)
- Destructive operations (organizations:*, account:*, KMS key deletion)

Effective permissions = (identity policy allows) intersect (boundary allows) minus (any explicit deny in either).

## License

MIT
