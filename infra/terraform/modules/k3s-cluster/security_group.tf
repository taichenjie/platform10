# ---------------------------------------------------------------------------
# Node security group.
#
# Ingress: only from other members of this group (node to node). Nothing else
# needs to connect in. SSM is outbound only, and the K3s API is reached
# through an SSM port-forward, never an open port.
#
# Egress: locked to what the node needs. Pod traffic leaves through the node,
# so these rules also limit what pods can reach.
#
# Time sync (169.254.169.123) and IMDS (169.254.169.254) are link-local and
# not filtered by security groups.
# ---------------------------------------------------------------------------
resource "aws_security_group" "node" {
  name        = "${var.name_prefix}-k3s-node-sg"
  description = "K3s node: node-to-node in, HTTPS and VPC DNS out."
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-k3s-node-sg"
  })
}

# Node to node. No effect with one node. Lets a second node join in M6 without
# opening anything to the wider VPC (flannel VXLAN, kubelet, K3s API).
resource "aws_vpc_security_group_ingress_rule" "node_from_nodes" {
  security_group_id            = aws_security_group.node.id
  description                  = "All traffic from other K3s nodes in this group"
  referenced_security_group_id = aws_security_group.node.id
  ip_protocol                  = "-1"
}

resource "aws_vpc_security_group_egress_rule" "node_to_nodes" {
  security_group_id            = aws_security_group.node.id
  description                  = "All traffic to other K3s nodes in this group"
  referenced_security_group_id = aws_security_group.node.id
  ip_protocol                  = "-1"
}

# K3s install, container image pulls, SSM and ECR endpoints, OS packages.
resource "aws_vpc_security_group_egress_rule" "node_https" {
  security_group_id = aws_security_group.node.id
  description       = "HTTPS out for K3s install, image pulls and AWS endpoints"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

# VPC DNS resolver lives at the VPC base address + 2, inside the VPC CIDR.
resource "aws_vpc_security_group_egress_rule" "node_dns_udp" {
  security_group_id = aws_security_group.node.id
  description       = "DNS over UDP to the VPC resolver"
  cidr_ipv4         = var.vpc_cidr
  ip_protocol       = "udp"
  from_port         = 53
  to_port           = 53
}

resource "aws_vpc_security_group_egress_rule" "node_dns_tcp" {
  security_group_id = aws_security_group.node.id
  description       = "DNS over TCP to the VPC resolver, for large responses"
  cidr_ipv4         = var.vpc_cidr
  ip_protocol       = "tcp"
  from_port         = 53
  to_port           = 53
}
