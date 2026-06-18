# ---------------------------------------------------------------------------
# Dev environment root.
#
# This environment composes modules; it does not define raw resources itself.
# The module is referenced by relative path now; in Q2 it will be sourced from
# the Terraform Registry by version once published.
# ---------------------------------------------------------------------------
module "vpc" {
  source = "../../modules/vpc"

  vpc_cidr                  = var.vpc_cidr
  vpc_name                  = var.vpc_name
  nat_instance_profile_name = aws_iam_instance_profile.ec2_ssm.name
  # enable_dns_support / enable_dns_hostnames intentionally omitted:
  # the module defaults them to true, which is required for private DNS on
  # the interface VPC endpoints (SSM/ECR) added later this month.
}
