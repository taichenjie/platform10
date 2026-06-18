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
  iam_instance_profile        = var.nat_instance_profile_name
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

# ---------------------------------------------------------------------------
# S3 VPC endpoint (gateway type).
# Traffic from private subnets to S3 stays on the AWS internal network
# instead of going out via the NAT instance. Free (no hourly charge, no
# data processing). Required for the Q2 remote Terraform state backend to
# avoid sending state file reads/writes out the NAT.
#
# Gateway endpoints work by adding a route to the route table — they do
# not create an ENI in a subnet.
# ---------------------------------------------------------------------------
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = {
    Name = "${var.vpc_name}-vpce-s3"
  }
}

# Region lookup. Used to build the regional service name for the S3
# endpoint without hardcoding the region in two places.
data "aws_region" "current" {}

# ---------------------------------------------------------------------------
# Security group for interface VPC endpoints (SSM, ECR).
# Endpoints are reached on HTTPS (443). Ingress is restricted to the VPC
# CIDR so only in-VPC clients can reach them. No egress rules: endpoints
# are servers, they receive connections, they don't initiate any.
# ---------------------------------------------------------------------------
resource "aws_security_group" "vpc_endpoints" {
  name        = "${var.vpc_name}-vpce-sg"
  description = "Allow HTTPS from the VPC to interface VPC endpoints (SSM, ECR)."
  vpc_id      = aws_vpc.this.id

  tags = {
    Name = "${var.vpc_name}-vpce-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "vpce_https_from_vpc" {
  security_group_id = aws_security_group.vpc_endpoints.id
  description       = "HTTPS from any address inside the VPC"
  cidr_ipv4         = var.vpc_cidr
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

# ---------------------------------------------------------------------------
# SSM family interface endpoints.
# All three are required for SSM Session Manager to work:
#   - ssm:          main SSM API
#   - ssmmessages:  WebSocket for interactive sessions
#   - ec2messages:  SSM Agent ↔ SSM communication
#
# Single-AZ placement (private-az1 only) is a deliberate cost decision
# documented in ADR-002. Workloads in private-az2 reach these endpoints
# cross-AZ; functionally fine for SSM's low traffic volume.
#
# private_dns_enabled = true makes ssm.ap-southeast-1.amazonaws.com
# resolve to the ENI in our VPC instead of the public AWS endpoint.
# Requires enable_dns_support + enable_dns_hostnames on the VPC, which
# are on by default in this module.
# ---------------------------------------------------------------------------
locals {
  ssm_endpoint_services = ["ssm", "ssmmessages", "ec2messages"]
}

resource "aws_vpc_endpoint" "ssm_family" {
  for_each = toset(local.ssm_endpoint_services)

  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${data.aws_region.current.region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private["private-az1"].id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.vpc_name}-vpce-${each.value}"
  }
}

# ---------------------------------------------------------------------------
# ECR interface endpoints.
# Two are required for ECR to work end-to-end:
#   - ecr.api: the ECR API (auth, repo metadata, tag lookups)
#   - ecr.dkr: the Docker Registry API (image layer push/pull)
#
# Image layer storage in ECR is backed by S3. The S3 gateway endpoint
# from above handles that traffic automatically, so all three endpoints
# (ecr.api + ecr.dkr + s3) work together for fully-private container
# image pulls.
#
# Single-AZ placement matches the SSM endpoints — see ADR-002.
# ---------------------------------------------------------------------------
locals {
  ecr_endpoint_services = ["ecr.api", "ecr.dkr"]
}

resource "aws_vpc_endpoint" "ecr" {
  for_each = toset(local.ecr_endpoint_services)

  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${data.aws_region.current.region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private["private-az1"].id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "${var.vpc_name}-vpce-${each.value}"
  }
}
