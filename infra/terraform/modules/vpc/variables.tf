variable "vpc_cidr" {
  description = "Primary IPv4 CIDR block for the VPC. Locked design: 10.0.0.0/16."
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block (e.g. 10.0.0.0/16)."
  }
}

variable "vpc_name" {
  description = "Name tag for the VPC and the base for child resource names."
  type        = string

  validation {
    condition     = length(var.vpc_name) > 0 && length(var.vpc_name) <= 64
    error_message = "vpc_name must be between 1 and 64 characters."
  }
}

variable "enable_dns_support" {
  description = "Enable DNS resolution via the VPC's .2 Route 53 Resolver. Required for private DNS on VPC endpoints later."
  type        = bool
  default     = true
}

variable "enable_dns_hostnames" {
  description = "Assign DNS hostnames to instances. Required for private DNS resolution on interface VPC endpoints (SSM/ECR)."
  type        = bool
  default     = true
}

variable "nat_instance_profile_name" {
  description = "Name of an IAM instance profile to attach to the NAT instance. Required for SSM Session Manager access. Defaults to null (no profile)."
  type        = string
  default     = null
}
