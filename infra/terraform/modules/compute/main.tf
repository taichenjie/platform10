# ---------------------------------------------------------------------------
# AMI lookup for the NAT instance.
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
  name        = "${var.name_prefix}-nat-sg"
  description = "NAT instance: allow all traffic from VPC, all egress."
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name_prefix}-nat-sg"
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
  # checkov:skip=CKV_AWS_135:t4g.nano does not support EBS optimization. Not configurable on this instance family. REMOVE IF the NAT moves to an instance family that supports it (e.g. m-series).
  # checkov:skip=CKV_AWS_126:Detailed (1-min) monitoring costs ~$2.10/mo and is unnecessary for a short-lived NAT under apply/destroy discipline. REMOVE IF the NAT becomes long-running or 1-min metrics are needed for an incident.
  ami                    = data.aws_ssm_parameter.al2023_arm64.value
  instance_type          = "t4g.nano"
  subnet_id              = var.subnet_id
  private_ip             = var.private_ip
  vpc_security_group_ids = [aws_security_group.nat.id]
  source_dest_check      = false
  iam_instance_profile   = var.instance_profile_name

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
    Name = "${var.name_prefix}-nat"
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
    Name = "${var.name_prefix}-nat-eip"
  }
}

resource "aws_eip_association" "nat" {
  instance_id   = aws_instance.nat.id
  allocation_id = aws_eip.nat.id
}
