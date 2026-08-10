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
  # checkov:skip=CKV_AWS_18:Access logging adds a second bucket and ongoing cost for near-zero value on a solo Terraform state bucket accessed a few times a day. REMOVE IF this bucket holds state for shared/production environments with audit requirements.
  # checkov:skip=CKV2_AWS_62:Event notifications are for event-driven pipelines off bucket activity. No such pipeline exists for this state bucket. REMOVE IF an event-driven workflow is later built on state changes.
  # checkov:skip=CKV_AWS_144:Cross-region replication doubles storage and adds a second bucket for a solo state file. REMOVE IF state must survive a full-region outage for production environments.
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

# Expire old state versions after 90 days. Versioning keeps every write so
# a bad state can be rolled back, but without this the old versions pile up
# forever. 90 days is a long rollback window while still bounding growth.
resource "aws_s3_bucket_lifecycle_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    id     = "expire-noncurrent-state-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }

  # Abort incomplete multipart uploads after 7 days. A failed upload leaves
  # orphaned parts that cost storage and never show up in the object list.
  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}
