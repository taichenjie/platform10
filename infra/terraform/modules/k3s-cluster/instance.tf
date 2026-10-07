# ---------------------------------------------------------------------------
# K3s server node, launched from the launch template.
#
# Version follows the template's latest version. Any template change
# (new K3s version, new AMI, new size) replaces this node. That replacement
# is the node rotation path used in M9.
# ---------------------------------------------------------------------------
resource "aws_instance" "server" {
  # checkov:skip=CKV_AWS_126:Detailed monitoring costs extra and is not needed for short apply/destroy sessions.
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
