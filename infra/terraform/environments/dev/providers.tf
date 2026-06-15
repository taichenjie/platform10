provider "aws" {
  region = "ap-southeast-1"

  # default_tags stamps every taggable resource this provider creates.
  # Declared once here; inherited by every resource. No per-resource repetition,
  # nothing forgotten. This is the FinOps + IaC-truth signal baked in from day one.
  default_tags {
    tags = {
      Project     = "platform10"
      Environment = "dev"
      ManagedBy   = "terraform"
      Owner       = "cj-admin"
    }
  }
}
