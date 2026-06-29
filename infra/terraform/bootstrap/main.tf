# ---------------------------------------------------------------------------
# S3 bucket for Terraform remote state.
#
# Versioning on: every state write creates a new version, so a bad write
# can be rolled back to the previous version.
# Encryption on: state files can contain resource attributes including
# secrets. Encrypted at rest with AWS-managed KMS key.
# Block Public Access on: state must never be publicly readable.
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "terraform_state" {
  bucket = "platform10-tfstate-${data.aws_caller_identity.current.account_id}"

  # Prevent accidental deletion. Terraform will refuse to destroy this
  # bucket unless you first set this to false and apply.
  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name = "platform10-terraform-state"
  }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    bucket_key_enabled = true

    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Account ID lookup for globally-unique bucket naming.
data "aws_caller_identity" "current" {}
