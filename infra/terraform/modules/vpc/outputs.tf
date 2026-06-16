output "vpc_id" {
  description = "ID of the VPC. Consumed by subnets, route tables, endpoints, and SGs."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "Primary CIDR of the VPC. Useful for SG rules scoped to in-VPC traffic."
  value       = aws_vpc.this.cidr_block
}

output "vpc_arn" {
  description = "ARN of the VPC. Useful for IAM policy conditions and cross-resource references."
  value       = aws_vpc.this.arn
}

output "public_subnet_definitions" {
  description = "Map of public subnet definitions (cidr + az), keyed by name. Drives subnet resource creation."
  value       = local.public_subnets
}

output "private_subnet_definitions" {
  description = "Map of private subnet definitions (cidr + az), keyed by name. Drives subnet resource creation."
  value       = local.private_subnets
}
