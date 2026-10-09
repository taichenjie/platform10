terraform {
  required_version = "~> 1.15.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
  # Bootstrap state lives in the bucket this layer creates (ADR-012).
  # Backend blocks cannot use variables, so the bucket name is literal,
  # matching environments/dev. CI is denied bootstrap/* by policy.
  backend "s3" {
    bucket       = "platform10-tfstate-471934606798"
    key          = "bootstrap/terraform.tfstate"
    region       = "ap-southeast-1"
    use_lockfile = true
    encrypt      = true
  }
}
