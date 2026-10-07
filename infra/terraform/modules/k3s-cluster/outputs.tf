output "instance_id" {
  description = "ID of the K3s server instance. Used by the apply script to wait for SSM."
  value       = aws_instance.server.id
}

output "private_ip" {
  description = "Private IP of the K3s server."
  value       = aws_instance.server.private_ip
}

output "security_group_id" {
  description = "ID of the node security group. A second node in M6 joins this group."
  value       = aws_security_group.node.id
}

output "launch_template_id" {
  description = "ID of the K3s server launch template."
  value       = aws_launch_template.server.id
}

output "launch_template_version" {
  description = "Launch template version the running node was built from."
  value       = aws_launch_template.server.latest_version
}

output "k3s_version" {
  description = "K3s release installed on the node."
  value       = var.k3s_version
}
