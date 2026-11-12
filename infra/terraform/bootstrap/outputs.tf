output "state_bucket_name" {
  description = "S3 bucket name for Terraform remote state."
  value       = aws_s3_bucket.terraform_state.id
}

output "state_bucket_arn" {
  description = "ARN of the state bucket."
  value       = aws_s3_bucket.terraform_state.arn
}

output "permission_boundary_arn" {
  description = "ARN of the platform10 permission boundary."
  value       = module.iam.permission_boundary_arn
}

output "ec2_ssm_instance_profile_name" {
  description = "Name of the EC2 SSM instance profile used by dev instances."
  value       = module.iam.ec2_ssm_instance_profile_name
}

output "ci_plan_role_arn" {
  description = "ARN of the read-only CI plan role."
  value       = module.iam.ci_plan_role_arn
}

output "ci_apply_role_arn" {
  description = "ARN of the CI apply role."
  value       = module.iam.ci_apply_role_arn
}
