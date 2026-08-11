# Compatibility requirements for the IAM module.
#
# required_version matches the VPC module for consistency across modules.
# The provider constraint is permissive (>= 6.0, minimum-not-pin) so a
# consumer stays free to choose its own exact provider version. No provider
# block here: provider config lives in the environment that calls this
# module, never in the module.
terraform {
  required_version = "~> 1.15.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }
}
