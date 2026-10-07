# ---------------------------------------------------------------------------
# Naming and placement
# ---------------------------------------------------------------------------
variable "name_prefix" {
  description = "Prefix for all resource names, e.g. platform10-dev."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.name_prefix))
    error_message = "name_prefix must be lowercase letters, numbers, and hyphens only."
  }
}

variable "vpc_id" {
  description = "ID of the VPC the node runs in. Used by the node security group."
  type        = string

  validation {
    condition     = can(regex("^vpc-[0-9a-f]+$", var.vpc_id))
    error_message = "vpc_id must look like vpc-xxxxxxxx."
  }
}

variable "vpc_cidr" {
  description = "VPC CIDR block. Scopes the node security group rules to traffic from inside the VPC."
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block, e.g. 10.0.0.0/16."
  }
}

variable "subnet_id" {
  description = "ID of the PRIVATE subnet for the node. The node never gets a public IP."
  type        = string

  validation {
    condition     = can(regex("^subnet-[0-9a-f]+$", var.subnet_id))
    error_message = "subnet_id must look like subnet-xxxxxxxx."
  }
}

variable "instance_profile_name" {
  description = "Name of the EC2 SSM instance profile created in bootstrap."
  type        = string
}

# ---------------------------------------------------------------------------
# Node sizing
# ---------------------------------------------------------------------------
variable "instance_type" {
  description = "EC2 instance type. Must be ARM (Graviton) to match the arm64 AMI."
  type        = string
  default     = "t4g.small"

  validation {
    condition     = can(regex("^(t4g|m7g|c7g|r7g)\\.", var.instance_type))
    error_message = "instance_type must be a Graviton (arm64) type such as t4g.small."
  }
}

variable "use_spot" {
  description = "Launch as Spot (true) or On-Demand (false). Set false only if Spot capacity is unavailable."
  type        = bool
  default     = true
}

variable "root_volume_size_gib" {
  description = "Root volume size in GiB. Holds the OS, K3s and container images. Confirmed by the M5 smoke test."
  type        = number
  default     = 20

  validation {
    condition     = var.root_volume_size_gib >= 16 && var.root_volume_size_gib <= 50
    error_message = "root_volume_size_gib must be between 16 and 50."
  }
}

# ---------------------------------------------------------------------------
# K3s
# ---------------------------------------------------------------------------
variable "k3s_version" {
  # Pinned one minor behind stable on purpose. On 2 Oct 2026 stable was
  # v1.36.5+k3s1. M9 upgrades this cluster to 1.36 as a real upgrade and
  # node rotation exercise. This is a staged version, not an unpatched one.
  description = "Exact K3s release to install, e.g. v1.35.9+k3s1."
  type        = string
  default     = "v1.35.9+k3s1"

  validation {
    condition     = can(regex("^v1\\.[0-9]+\\.[0-9]+\\+k3s[0-9]+$", var.k3s_version))
    error_message = "k3s_version must be an exact release like v1.35.9+k3s1, never a channel name like stable."
  }
}

variable "tags" {
  description = "Extra tags merged onto every resource. Provider default_tags still apply."
  type        = map(string)
  default     = {}
}
