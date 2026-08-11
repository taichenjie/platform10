# ---------------------------------------------------------------------------
# IAM for the dev environment.
#
# The IAM resources (permission boundary, EC2 SSM role, instance profile)
# used to be defined inline here. They were extracted into modules/iam so
# they can be reused and published to the Terraform Registry.
#
# The moved blocks below tell Terraform that each resource changed address
# (from root module to module.iam) but is the SAME resource in AWS. Without
# them, Terraform would destroy the old resources and create new ones. With
# them, Terraform only updates its state pointer. The plan shows zero
# destroys.
#
# name_prefix is passed as "platform10-dev" so every resource name stays
# byte-for-byte identical to what it was inline. A changed name would force
# a destroy and recreate.
# ---------------------------------------------------------------------------
module "iam" {
  source      = "../../modules/iam"
  name_prefix = "platform10-dev"
}

# ---------------------------------------------------------------------------
# Moved blocks: map each old root-module address to its new module.iam
# address. These are safe to remove in a later commit once the apply has
# migrated state. Keep them through the extraction PR and its apply.
# ---------------------------------------------------------------------------
moved {
  from = aws_iam_policy.permission_boundary
  to   = module.iam.aws_iam_policy.permission_boundary
}

moved {
  from = aws_iam_role.ec2_ssm
  to   = module.iam.aws_iam_role.ec2_ssm
}

moved {
  from = aws_iam_role_policy_attachment.ec2_ssm_core
  to   = module.iam.aws_iam_role_policy_attachment.ec2_ssm_core
}

moved {
  from = aws_iam_instance_profile.ec2_ssm
  to   = module.iam.aws_iam_instance_profile.ec2_ssm
}

# ---------------------------------------------------------------------------
# Environment-level outputs, now sourced from the module instead of the
# inline resources.
# ---------------------------------------------------------------------------
output "permission_boundary_arn" {
  description = "ARN of the platform10 permission boundary."
  value       = module.iam.permission_boundary_arn
}

output "ec2_ssm_instance_profile_name" {
  description = "Name of the EC2 SSM instance profile."
  value       = module.iam.ec2_ssm_instance_profile_name
}
