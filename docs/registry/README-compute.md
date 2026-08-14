# terraform-aws-platform10-compute

Terraform module for the Platform 10 NAT instance. Creates a self-managed NAT on a t4g.nano ARM Graviton instance with an Elastic IP, security group, and cloud-init user data for IP forwarding and iptables MASQUERADE.

Designed for the Platform 10 project. Replaces the managed NAT Gateway ($32+/month) with a self-managed instance (~$4/month).

## Usage

```hcl
module "compute" {
  source = "taichenjie/platform10-compute/aws"

  name_prefix           = "platform10-dev"
  vpc_id                = module.vpc.vpc_id
  vpc_cidr              = module.vpc.vpc_cidr
  subnet_id             = module.vpc.public_subnet_ids["public-az1"]
  instance_profile_name = module.iam.ec2_ssm_instance_profile_name
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| name_prefix | Prefix for all compute resource names (e.g. platform10-dev) | string | n/a | yes |
| vpc_id | ID of the VPC for the NAT security group | string | n/a | yes |
| vpc_cidr | VPC CIDR block for NAT SG ingress and MASQUERADE scope | string | n/a | yes |
| subnet_id | ID of the public subnet where the NAT instance is placed | string | n/a | yes |
| instance_profile_name | Name of the IAM instance profile to attach | string | n/a | yes |
| private_ip | Fixed private IP for the NAT instance | string | 10.0.0.10 | no |

## Outputs

| Name | Description |
|------|-------------|
| nat_primary_network_interface_id | Primary ENI ID of the NAT instance (used by VPC module for private route) |
| nat_instance_id | Instance ID of the NAT instance |
| nat_eip_public_ip | Public IP of the NAT Elastic IP |

## Requirements

| Name | Version |
|------|---------|
| terraform | ~> 1.15.5 |
| aws | >= 6.0 |

## Design notes

- AMI fetched dynamically via SSM parameter (always latest AL2023 ARM64).
- source_dest_check = false (required for any instance forwarding packets for other hosts).
- IMDSv2 enforced (blocks SSRF credential theft via IMDS).
- user_data_replace_on_change = true (instance is replaced when the cloud-init script changes).
- EIP provides a stable public address that survives instance replacement.

## License

MIT
