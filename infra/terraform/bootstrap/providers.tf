provider "aws" {
  region = "ap-southeast-1"

  default_tags {
    tags = {
      Project     = "platform10"
      Environment = "bootstrap"
      ManagedBy   = "terraform"
      Owner       = "cj-admin"
    }
  }
}
