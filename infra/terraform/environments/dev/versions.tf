terraform {
  # Pin Terraform itself. The ~> operator allows patch bumps (1.15.x) but
  # blocks a minor/major jump (1.16+)
  required_version = "~> 1.15.5"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # Pin the AWS provider to the 6.x line. Same logic: patch/minor updates
      version = "~> 6.0"
    }
  }
}
