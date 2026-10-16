output "k3s_instance_id" {
  description = "K3s server instance ID. Used by the apply script to wait for SSM."
  value       = module.k3s_cluster.instance_id
}

output "k3s_private_ip" {
  description = "K3s server private IP."
  value       = module.k3s_cluster.private_ip
}

output "k3s_version" {
  description = "K3s release installed on the server."
  value       = module.k3s_cluster.k3s_version
}
