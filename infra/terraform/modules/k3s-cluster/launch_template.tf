# Latest Amazon Linux 2023 arm64 AMI. Same lookup as the NAT instance.
data "aws_ssm_parameter" "al2023_arm64" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

# ---------------------------------------------------------------------------
# Launch template: the recipe for a K3s server node.
# Each change creates a new version. The instance follows the latest version.
# ---------------------------------------------------------------------------
resource "aws_launch_template" "server" {
  # checkov:skip=CKV_AWS_126:Detailed monitoring costs extra and is not needed for short apply/destroy sessions.
  name                   = "${var.name_prefix}-k3s-server-lt"
  description            = "K3s server node. K3s ${var.k3s_version}."
  update_default_version = true

  # Section 1: what to run on.
  image_id      = data.aws_ssm_parameter.al2023_arm64.value
  instance_type = var.instance_type
  ebs_optimized = true

  # Standard credits: the node is throttled when burst credits run out,
  # instead of billing for extra CPU. No surprise charges.
  credit_specification {
    cpu_credits = "standard"
  }

  # Section 2: identity and firewall.
  iam_instance_profile {
    name = var.instance_profile_name
  }
  vpc_security_group_ids = [aws_security_group.node.id]

  # Section 3: metadata service locked down.
  # IMDSv2 only. Hop limit 1 means pods cannot reach the metadata service
  # through the node, so a compromised pod cannot take the node's AWS role.
  # Revisit in M8: the EBS CSI driver may need a hop limit of 2.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  # Section 4: encrypted root disk, deleted with the instance.
  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_type           = "gp3"
      volume_size           = var.root_volume_size_gib
      encrypted             = true
      delete_on_termination = true
    }
  }

  # Section 5: Spot or On-Demand, and the first-boot script.
  dynamic "instance_market_options" {
    for_each = var.use_spot ? [1] : []

    content {
      market_type = "spot"

      spot_options {
        spot_instance_type             = "one-time"
        instance_interruption_behavior = "terminate"
      }
    }
  }

  user_data = base64encode(templatefile("${path.module}/files/k3s-server-userdata.sh.tftpl", {
    k3s_version = var.k3s_version
  }))

  # Tag the root volume so the orphan audit can find it by name.
  tag_specifications {
    resource_type = "volume"
    tags = merge(var.tags, {
      Name = "${var.name_prefix}-k3s-server-root"
    })
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-k3s-server-lt"
  })
}
