# oidc.tf — GitHub Actions OIDC federation for CI/CD authentication.
#
# Replaces static IAM access keys with short-lived STS credentials.
# This file holds the account-wide OIDC provider and the locals the CI
# roles share. The roles themselves are in ci_roles.tf: a read-only plan
# role and an apply role behind the production-apply environment
# (ADR-005 amendment 1). The shared platform10-github-actions-ci role
# was removed on 12 Nov 2026.

locals {
  github_oidc_issuer = "token.actions.githubusercontent.com"
  github_oidc_url    = "https://${local.github_oidc_issuer}"
  state_bucket_arn   = "arn:aws:s3:::platform10-tfstate-471934606798"
}

# Registers GitHub's OIDC token service as a trusted identity
# provider in this AWS account. Created once, account-wide.
resource "aws_iam_openid_connect_provider" "github_actions" {
  url             = local.github_oidc_url
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["ffffffffffffffffffffffffffffffffffffffff"]

  tags = {
    Name = "${var.name_prefix}-github-oidc-provider"
  }
}

# Used to scope the K3s EventBridge and CloudWatch Logs permissions in
# ci_roles.tf.
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region
  k3s_prefix = "${var.name_prefix}-k3s"
}
