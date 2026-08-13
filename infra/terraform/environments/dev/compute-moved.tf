# ---------------------------------------------------------------------------
# Moved blocks for the compute extraction.
#
# These resources were extracted from modules/vpc into modules/compute.
# Each moved block tells Terraform the old and new address are the same
# resource. Terraform updates its state pointer instead of destroying and
# recreating. Safe to remove in a later commit once the apply has migrated
# state.
# ---------------------------------------------------------------------------
moved {
  from = module.vpc.aws_security_group.nat
  to   = module.compute.aws_security_group.nat
}

moved {
  from = module.vpc.aws_vpc_security_group_ingress_rule.nat_from_vpc
  to   = module.compute.aws_vpc_security_group_ingress_rule.nat_from_vpc
}

moved {
  from = module.vpc.aws_vpc_security_group_egress_rule.nat_to_internet
  to   = module.compute.aws_vpc_security_group_egress_rule.nat_to_internet
}

moved {
  from = module.vpc.aws_instance.nat
  to   = module.compute.aws_instance.nat
}

moved {
  from = module.vpc.aws_eip.nat
  to   = module.compute.aws_eip.nat
}

moved {
  from = module.vpc.aws_eip_association.nat
  to   = module.compute.aws_eip_association.nat
}
