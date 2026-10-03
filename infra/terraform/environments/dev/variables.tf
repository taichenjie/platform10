variable "vpc_cidr" {
  description = "Primary IPv4 CIDR for the dev VPC."
  type        = string
}

variable "vpc_name" {
  description = "Name tag for the dev VPC."
  type        = string
}

variable "ec2_ssm_instance_profile_name" {
  description = "Name of the EC2 SSM instance profile created in bootstrap."
  type        = string
  default     = "platform10-dev-ec2-ssm-profile"

  validation {
    condition     = can(regex("^[\\w+=,.@-]{1,128}$", var.ec2_ssm_instance_profile_name))
    error_message = "Must be a valid IAM instance profile name: 1 to 128 characters, letters, digits and +=,.@_-"
  }
}
