# Return values of the IAM module. These are the only way information
# escapes the module to whatever called it.

output "permission_boundary_arn" {
  description = "ARN of the permission boundary. Attach this to every non-root role created in this environment."
  value       = aws_iam_policy.permission_boundary.arn
}

output "ec2_ssm_instance_profile_name" {
  description = "Name of the EC2 SSM instance profile. Pass this to any EC2 instance that should be reachable via SSM."
  value       = aws_iam_instance_profile.ec2_ssm.name
}

output "ec2_ssm_role_name" {
  description = "Name of the EC2 SSM role. Exposed for future policy attachments or auditing."
  value       = aws_iam_role.ec2_ssm.name
}
output "github_actions_ci_role_arn" {
  description = "ARN of the GitHub Actions CI role. Used in workflow YAML for role-to-assume."
  value       = aws_iam_role.github_actions_ci.arn
}
