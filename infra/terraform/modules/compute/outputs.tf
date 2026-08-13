output "nat_primary_network_interface_id" {
  description = "Primary ENI ID of the NAT instance. The VPC module uses this as the target for the private route table default route (0.0.0.0/0 -> NAT)."
  value       = aws_instance.nat.primary_network_interface_id
}

output "nat_instance_id" {
  description = "Instance ID of the NAT instance."
  value       = aws_instance.nat.id
}

output "nat_eip_public_ip" {
  description = "Public IP of the NAT Elastic IP."
  value       = aws_eip.nat.public_ip
}
