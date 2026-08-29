# ---------------------------------------------------------------------------
# IAM for the dev environment.
#
# The IAM resources (permission boundary, EC2 SSM role, instance profile,
# OIDC federation) live in modules/iam. This file calls the module and
# passes through its outputs.
# ---------------------------------------------------------------------------
module "iam" {
  source      = "../../modules/iam"
  name_prefix = "platform10-dev"
}
# ---------------------------------------------------------------------------
# Environment-level outputs, sourced from the module.
# ---------------------------------------------------------------------------
output "permission_boundary_arn" {
  description = "ARN of the platform10 permission boundary."
  value       = module.iam.permission_boundary_arn
}
output "ec2_ssm_instance_profile_name" {
  description = "Name of the EC2 SSM instance profile."
  value       = module.iam.ec2_ssm_instance_profile_name
}
output "github_actions_ci_role_arn" {
  description = "ARN of the GitHub Actions CI role for OIDC federation."
  value       = module.iam.github_actions_ci_role_arn
}
