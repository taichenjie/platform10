# IAM lives in bootstrap, which is never destroyed. Dev only reads it.
# Plan fails here if bootstrap has not been applied, which is the intent.
data "aws_iam_instance_profile" "ec2_ssm" {
  name = var.ec2_ssm_instance_profile_name
}
