# terraform-aws-platform10-vpc

Terraform module for the Platform 10 VPC. Creates a dual-AZ network with public and private subnets, an internet gateway, route tables, S3 gateway endpoint, SSM and ECR interface endpoints, and a locked default security group.

Designed for the Platform 10 project. The module hardcodes two availability zones in ap-southeast-1 and expects a NAT network interface ID as input for the private route table default route.

## Usage

```hcl
module "vpc" {
  source = "taichenjie/platform10-vpc/aws"

  vpc_cidr                 = "10.0.0.0/16"
  vpc_name                 = "platform10-dev"
  nat_network_interface_id = module.compute.nat_primary_network_interface_id
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| vpc_cidr | Primary IPv4 CIDR block for the VPC | string | n/a | yes |
| vpc_name | Name tag for the VPC and base for child resource names | string | n/a | yes |
| nat_network_interface_id | Primary ENI ID of the NAT instance for the private route table default route | string | n/a | yes |
| enable_dns_support | Enable DNS resolution via the VPC Route 53 Resolver | bool | true | no |
| enable_dns_hostnames | Assign DNS hostnames to instances | bool | true | no |

## Outputs

| Name | Description |
|------|-------------|
| vpc_id | ID of the VPC |
| vpc_cidr | Primary CIDR of the VPC |
| vpc_arn | ARN of the VPC |
| public_subnet_ids | Map of public subnet IDs keyed by name |
| private_subnet_ids | Map of private subnet IDs keyed by name |
| public_subnet_definitions | Map of public subnet definitions (cidr + az) keyed by name |
| private_subnet_definitions | Map of private subnet definitions (cidr + az) keyed by name |

## Requirements

| Name | Version |
|------|---------|
| terraform | ~> 1.15.5 |
| aws | >= 6.0 |

## Architecture decisions

- Subnet CIDRs computed with cidrsubnet(), not hardcoded.
- Public subnets have map_public_ip_on_launch = false. Nothing gets a public IP automatically.
- S3 gateway endpoint (free) routes private subnet S3 traffic over the AWS backbone.
- SSM and ECR interface endpoints are single-AZ (cost decision, see ADR-002 in the main repo).
- Default security group adopted and locked (no ingress, no egress).

## License

MIT
