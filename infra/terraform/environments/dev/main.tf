# ---------------------------------------------------------------------------
# Dev environment root.
#
# This environment composes modules; it does not define raw resources itself.
# The modules are referenced by relative path now; in Q2 they will be sourced
# from the Terraform Registry by version once published.
#
# Dependency order (Terraform resolves this automatically from references):
#   1. VPC creates subnets (no NAT needed yet)
#   2. Compute creates NAT instance in the public subnet (needs subnet from 1)
#   3. VPC creates the private route (needs NAT ENI from 2)
# ---------------------------------------------------------------------------
module "vpc" {
  source   = "../../modules/vpc"
  vpc_cidr = var.vpc_cidr
  vpc_name = var.vpc_name

  nat_network_interface_id = module.compute.nat_primary_network_interface_id
}

module "compute" {
  source = "../../modules/compute"

  name_prefix           = var.vpc_name
  vpc_id                = module.vpc.vpc_id
  vpc_cidr              = var.vpc_cidr
  subnet_id             = module.vpc.public_subnet_ids["public-az1"]
  instance_profile_name = module.iam.ec2_ssm_instance_profile_name
}
