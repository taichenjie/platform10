# ---------------------------------------------------------------------------
# Locals: encode the locked subnet design as derived values, not magic strings.
#
# Subnets are computed from the VPC CIDR with cidrsubnet() rather than
# hardcoded. This proves the math is correct by construction and means a
# change to vpc_cidr cascades correctly instead of leaving stale subnet
# strings behind.
#
# cidrsubnet(prefix, newbits, netnum):
#   newbits = how many bits to ADD to the prefix (16 -> /24 means newbits = 8)
#   netnum  = which subnet block, counting in /24-sized steps (NOT raw addresses)
#
# Locked design (10.0.0.0/16, carved into /24s):
#   netnum 0 -> 10.0.0.0/24  Public  AZ1 (NAT instance lives here)
#   netnum 1 -> 10.0.1.0/24  Public  AZ2 (spare)
#   netnum 2 -> 10.0.2.0/24  Private AZ1 (RPC node)
#   netnum 3 -> 10.0.3.0/24  Private AZ2 (K3s node, future)
# ---------------------------------------------------------------------------
locals {
  azs = ["ap-southeast-1a", "ap-southeast-1b"]

  public_subnets = {
    "public-az1" = { cidr = cidrsubnet(var.vpc_cidr, 8, 0), az = local.azs[0] }
    "public-az2" = { cidr = cidrsubnet(var.vpc_cidr, 8, 1), az = local.azs[1] }
  }

  private_subnets = {
    "private-az1" = { cidr = cidrsubnet(var.vpc_cidr, 8, 2), az = local.azs[0] }
    "private-az2" = { cidr = cidrsubnet(var.vpc_cidr, 8, 3), az = local.azs[1] }
  }
}

# ---------------------------------------------------------------------------
# The VPC itself.
# ---------------------------------------------------------------------------
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  instance_tenancy     = "default"
  enable_dns_support   = var.enable_dns_support
  enable_dns_hostnames = var.enable_dns_hostnames

  tags = {
    Name = var.vpc_name
  }
}
