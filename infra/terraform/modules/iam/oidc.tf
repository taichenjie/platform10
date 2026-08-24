# oidc.tf — GitHub Actions OIDC federation for CI/CD authentication.
#
# Replaces static IAM access keys with short-lived STS credentials.
# The trust policy pins assumption to repo:taichenjie/platform10 on
# main branch (push/dispatch) and pull request contexts only.
# Feature branches, forks, and other workflow contexts are rejected.

locals {
  github_oidc_issuer = "token.actions.githubusercontent.com"
  github_oidc_url    = "https://${local.github_oidc_issuer}"
  state_bucket_arn   = "arn:aws:s3:::platform10-tfstate-471934606798"

  # Sub claims allowed to assume the CI role.
  # Push/dispatch on main: plan and apply workflows.
  # Pull request: plan-only workflow on PRs targeting main.
  github_oidc_allowed_subs = [
    "repo:taichenjie/platform10:ref:refs/heads/main",
    "repo:taichenjie/platform10:pull_request",
  ]
}

# ---------------------------------------------------------------
# Trust policy: WHO can assume the CI role.
# ---------------------------------------------------------------

data "aws_iam_policy_document" "github_actions_trust" {
  statement {
    sid     = "GitHubActionsOIDC"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github_actions.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.github_oidc_issuer}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.github_oidc_issuer}:sub"
      values   = local.github_oidc_allowed_subs
    }
  }
}

# ---------------------------------------------------------------
# Permission policy: WHAT the CI role can do once assumed.
#
# Least-privilege for the current 32-resource stack. Will expand
# in Q3 when K3s resources land. Each expansion is a tracked
# policy change, not an unaudited scope creep.
# ---------------------------------------------------------------

data "aws_iam_policy_document" "github_actions_permissions" {

  # EC2 and VPC management.
  # Most EC2/VPC actions do not support resource-level restrictions.
  # The permission boundary remains the hard ceiling.
  statement {
    sid    = "EC2VPCManagement"
    effect = "Allow"
    actions = [
      # Read (plan needs all of these)
      "ec2:Describe*",

      # VPC lifecycle
      "ec2:CreateVpc",
      "ec2:DeleteVpc",
      "ec2:ModifyVpcAttribute",

      # Subnets
      "ec2:CreateSubnet",
      "ec2:DeleteSubnet",
      "ec2:ModifySubnetAttribute",

      # Route tables and routes
      "ec2:CreateRouteTable",
      "ec2:DeleteRouteTable",
      "ec2:CreateRoute",
      "ec2:DeleteRoute",
      "ec2:ReplaceRoute",
      "ec2:AssociateRouteTable",
      "ec2:DisassociateRouteTable",

      # Internet gateway
      "ec2:CreateInternetGateway",
      "ec2:DeleteInternetGateway",
      "ec2:AttachInternetGateway",
      "ec2:DetachInternetGateway",

      # VPC endpoints (SSM, ECR, S3)
      "ec2:CreateVpcEndpoint",
      "ec2:DeleteVpcEndpoints",
      "ec2:ModifyVpcEndpoint",

      # Instances (NAT instance, future compute)
      "ec2:RunInstances",
      "ec2:TerminateInstances",
      "ec2:ModifyInstanceAttribute",

      # Elastic IPs
      "ec2:AllocateAddress",
      "ec2:ReleaseAddress",
      "ec2:AssociateAddress",
      "ec2:DisassociateAddress",

      # Security groups
      "ec2:CreateSecurityGroup",
      "ec2:DeleteSecurityGroup",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:AuthorizeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupEgress",

      # Key pairs
      "ec2:CreateKeyPair",
      "ec2:DeleteKeyPair",
      "ec2:ImportKeyPair",

      # Tagging
      "ec2:CreateTags",
      "ec2:DeleteTags",
    ]
    resources = ["*"]
  }

  # IAM management for roles, policies, instance profiles, OIDC provider.
  statement {
    sid    = "IAMManagement"
    effect = "Allow"
    actions = [
      # Roles
      "iam:CreateRole",
      "iam:GetRole",
      "iam:DeleteRole",
      "iam:UpdateRole",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:PassRole",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole",

      # Policies
      "iam:CreatePolicy",
      "iam:GetPolicy",
      "iam:DeletePolicy",
      "iam:GetPolicyVersion",
      "iam:CreatePolicyVersion",
      "iam:DeletePolicyVersion",
      "iam:ListPolicyVersions",
      "iam:TagPolicy",
      "iam:UntagPolicy",

      # Policy attachments
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",

      # Instance profiles
      "iam:CreateInstanceProfile",
      "iam:GetInstanceProfile",
      "iam:DeleteInstanceProfile",
      "iam:AddRoleToInstanceProfile",
      "iam:RemoveRoleFromInstanceProfile",
      "iam:TagInstanceProfile",
      "iam:UntagInstanceProfile",

      # OIDC provider (self-management)
      "iam:CreateOpenIDConnectProvider",
      "iam:GetOpenIDConnectProvider",
      "iam:DeleteOpenIDConnectProvider",
      "iam:UpdateOpenIDConnectProviderThumbprint",
      "iam:TagOpenIDConnectProvider",
      "iam:UntagOpenIDConnectProvider",
      "iam:ListOpenIDConnectProviders",
    ]
    resources = ["*"]
  }

  # S3 state bucket access. Scoped to the state bucket only.
  # Covers state file read/write and S3-native lock file operations.
  statement {
    sid    = "S3StateBucket"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
    ]
    resources = [
      local.state_bucket_arn,
      "${local.state_bucket_arn}/*",
    ]
  }

  # SSM parameter read for AMI lookups. The compute module resolves
  # the latest AL2023 AMI via an SSM public parameter.
  statement {
    sid    = "SSMParameterRead"
    effect = "Allow"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
    ]
    resources = ["*"]
  }

  # STS caller identity check. The AWS provider calls this on init
  # to verify credentials are valid.
  statement {
    sid       = "STSIdentity"
    effect    = "Allow"
    actions   = ["sts:GetCallerIdentity"]
    resources = ["*"]
  }
}

# ---------------------------------------------------------------
# Resources
# ---------------------------------------------------------------

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

# The role GitHub Actions assumes via OIDC. Trust policy restricts
# assumption to main branch and pull request contexts. Permission
# boundary caps the ceiling, same as every other principal.
resource "aws_iam_role" "github_actions_ci" {
  name                 = "platform10-github-actions-ci"
  assume_role_policy   = data.aws_iam_policy_document.github_actions_trust.json
  permissions_boundary = aws_iam_policy.permission_boundary.arn
  max_session_duration = 3600

  tags = {
    Name = "${var.name_prefix}-github-actions-ci-role"
  }
}

# Wraps the permission policy document into a managed policy.
resource "aws_iam_policy" "github_actions_ci" {
  name   = "platform10-github-actions-ci"
  policy = data.aws_iam_policy_document.github_actions_permissions.json

  tags = {
    Name = "${var.name_prefix}-github-actions-ci-policy"
  }
}

# Attaches the permission policy to the CI role.
resource "aws_iam_role_policy_attachment" "github_actions_ci" {
  role       = aws_iam_role.github_actions_ci.name
  policy_arn = aws_iam_policy.github_actions_ci.arn
}
