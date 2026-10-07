# ---------------------------------------------------------------------------
# K3s server node, launched from the launch template.
#
# Version follows the template's latest version. Any template change
# (new K3s version, new AMI, new size) replaces this node. That replacement
# is the node rotation path used in M9.
#
# All settings live in the launch template. Checkov evaluates this resource
# without following the launch_template reference, so it reports settings
# the template already enforces. Each skip names where the setting lives.
# REMOVE A SKIP if that setting is ever moved out of the launch template.
# ---------------------------------------------------------------------------
resource "aws_instance" "server" {
  # checkov:skip=CKV_AWS_126:Detailed monitoring costs extra and is not needed for short apply/destroy sessions.
  # checkov:skip=CKV_AWS_8:Root volume encrypted in launch_template.tf (block_device_mappings, encrypted = true).
  # checkov:skip=CKV_AWS_79:IMDSv2 required in launch_template.tf (metadata_options, http_tokens = required).
  # checkov:skip=CKV_AWS_135:EBS optimization set in launch_template.tf (ebs_optimized = true).
  # checkov:skip=CKV2_AWS_41:IAM instance profile attached in launch_template.tf (iam_instance_profile).
  subnet_id = var.subnet_id

  launch_template {
    id      = aws_launch_template.server.id
    version = aws_launch_template.server.latest_version
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-k3s-server"
    Role = "k3s-server"
  })
}
