variable "name_prefix" {
  description = "Prefix for all compute resource names, e.g. platform10-dev."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.name_prefix))
    error_message = "name_prefix must be lowercase letters, numbers, and hyphens only."
  }
}

variable "vpc_id" {
  description = "ID of the VPC. Used by the NAT security group."
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block. Used for the NAT SG ingress rule and the MASQUERADE scope in user data."
  type        = string
}

variable "subnet_id" {
  description = "ID of the public subnet where the NAT instance is placed."
  type        = string
}

variable "instance_profile_name" {
  description = "Name of the IAM instance profile to attach to the NAT instance."
  type        = string
}

variable "private_ip" {
  description = "Fixed private IP for the NAT instance."
  type        = string
  default     = "10.0.0.10"
}
