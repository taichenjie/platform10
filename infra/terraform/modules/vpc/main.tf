# ---------------------------------------------------------------------------
# Subnet CIDRs are calculated from the VPC CIDR, not hardcoded.
# If the VPC CIDR changes, the subnets update with it.
#
# cidrsubnet(prefix, newbits, netnum):
#   newbits = bits to add to the prefix (16 + 8 = /24 subnets)
#   netnum  = which subnet block to pick (0 = first, 1 = second, etc.)
#
# Locked design on 10.0.0.0/16:
#   netnum 0 -> 10.0.0.0/24  Public  AZ1 (NAT instance)
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
# The VPC.
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

# ---------------------------------------------------------------------------
# Public subnets.
# map_public_ip_on_launch = false so that nothing launched here gets a
# public IP automatically. The only resource that needs a public IP is the
# NAT instance, which gets one explicitly via an Elastic IP later.
# ---------------------------------------------------------------------------
resource "aws_subnet" "public" {
  for_each = local.public_subnets

  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.vpc_name}-${each.key}"
    Tier = "public"
  }
}

# ---------------------------------------------------------------------------
# Private subnets.
# No public IPs. Internet access only via the NAT instance, set in the
# private route table.
# ---------------------------------------------------------------------------
resource "aws_subnet" "private" {
  for_each = local.private_subnets

  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value.cidr
  availability_zone = each.value.az

  tags = {
    Name = "${var.vpc_name}-${each.key}"
    Tier = "private"
  }
}

# ---------------------------------------------------------------------------
# Internet Gateway.
# Allows traffic between the VPC and the internet. Required for the public
# route table's 0.0.0.0/0 route to work.
# ---------------------------------------------------------------------------
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.vpc_name}-igw"
  }
}

# ---------------------------------------------------------------------------
# Public route table.
# Sends all non-local traffic out the IGW. Associated with both public
# subnets so anything in them can reach the internet (the NAT instance
# being the only thing that will).
# ---------------------------------------------------------------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name = "${var.vpc_name}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# ---------------------------------------------------------------------------
# AMI lookup: latest Amazon Linux 2023 ARM64 from AWS's public SSM parameter.
# AWS publishes and updates this parameter, so we always get the current AMI
# without hardcoding an ID that goes stale.
# ---------------------------------------------------------------------------
data "aws_ssm_parameter" "al2023_arm64" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

# ---------------------------------------------------------------------------
# NAT instance security group.
# Ingress: anything from inside the VPC (private subnets route through here).
# Egress:  anywhere (the NAT forwards traffic out to the internet).
# ---------------------------------------------------------------------------
resource "aws_security_group" "nat" {
  name        = "${var.vpc_name}-nat-sg"
  description = "NAT instance: allow all traffic from VPC, all egress."
  vpc_id      = aws_vpc.this.id

  tags = {
    Name = "${var.vpc_name}-nat-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "nat_from_vpc" {
  security_group_id = aws_security_group.nat.id
  description       = "Allow all traffic from VPC CIDR (private subnets route through this NAT)"
  cidr_ipv4         = var.vpc_cidr
  ip_protocol       = "-1"
}

resource "aws_vpc_security_group_egress_rule" "nat_to_internet" {
  security_group_id = aws_security_group.nat.id
  description       = "Allow all outbound traffic (NAT forwards VPC traffic to the internet)"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# ---------------------------------------------------------------------------
# NAT instance.
# t4g.nano (ARM Graviton, cheapest current generation). Lives in the public
# AZ1 subnet with a fixed private IP from the locked design.
#
# source_dest_check = false is the single most important setting here. By
# default AWS drops any packet whose source or destination IP doesn't match
# the instance's own IP. A NAT does exactly that — it forwards packets that
# belong to other hosts. Turning the check off is what makes NAT possible.
# ---------------------------------------------------------------------------
resource "aws_instance" "nat" {
  ami                         = data.aws_ssm_parameter.al2023_arm64.value
  instance_type               = "t4g.nano"
  subnet_id                   = aws_subnet.public["public-az1"].id
  private_ip                  = "10.0.0.10"
  vpc_security_group_ids      = [aws_security_group.nat.id]
  source_dest_check           = false
  associate_public_ip_address = false

  user_data = templatefile("${path.module}/files/nat-userdata.sh", {
    vpc_cidr = var.vpc_cidr
  })

  # If the user_data script changes, replace the instance so the new script
  # actually runs. Without this Terraform sees user_data is a "first boot
  # only" field and ignores the change.
  user_data_replace_on_change = true

  # IMDSv2 only. Blocks the SSRF attack class where a compromised process
  # tricks the instance into handing over its IAM credentials via IMDS.
  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 8
    encrypted   = true
  }

  tags = {
    Name = "${var.vpc_name}-nat"
    Role = "nat"
  }
}

# ---------------------------------------------------------------------------
# Elastic IP for the NAT instance.
# A stable public IP that survives instance replacement. Free while attached
# to a running instance; charged ~$0.005/hour when unattached, which is the
# orphan-billing risk if destroy ever leaves it behind. Tied to the instance
# below so destroy cleans both up together.
# ---------------------------------------------------------------------------
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${var.vpc_name}-nat-eip"
  }
}

resource "aws_eip_association" "nat" {
  instance_id   = aws_instance.nat.id
  allocation_id = aws_eip.nat.id
}

# ---------------------------------------------------------------------------
# Private route table.
# Empty by default — routes are added as separate aws_route resources below.
# This pattern is required because the private RT will get more routes later
# (the S3 VPC endpoint prefix list). Mixing inline routes with separate
# aws_route resources on the same table causes Terraform to fight itself.
# ---------------------------------------------------------------------------
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.vpc_name}-private-rt"
  }
}

# ---------------------------------------------------------------------------
# Default route via the NAT instance.
# Targets the NAT's primary ENI, not the instance ID directly. Routing via
# the ENI is the documented pattern and survives instance replacement
# cleanly as long as the new instance gets the same primary ENI.
# ---------------------------------------------------------------------------
resource "aws_route" "private_default" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = aws_instance.nat.primary_network_interface_id
}

# ---------------------------------------------------------------------------
# Associate both private subnets with the private route table.
# Without this they fall back to the VPC's default route table, which has
# no internet route — private instances would be unable to reach anything
# outside the VPC.
# ---------------------------------------------------------------------------
resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}
