# ci_roles.tf — split CI roles (review #3, M6, ADR-005 amendment).
#
# One role per job, instead of one write-capable role for everything.
#   platform10-ci-plan   read-only. PR plans and the apply workflow's plan job.
#   platform10-ci-apply  write. Only the apply job, behind production-apply.
#
# Plan code from any PR runs with the plan role, so it gets reads and the
# state lock, never infra writes. Apply runs only after a reviewer approves
# a saved plan they can read.
#
# Permissions are split into two documents.
#   ci_read   everything a plan or refresh calls. Attached to both roles,
#             because apply also reads (refresh during apply, provider reads
#             after create).
#   ci_write  every mutating action. Attached to the apply role only.

locals {
  github_repo_sub_prefix = "repo:taichenjie/platform10"

  # Plan role: PRs to main, and the apply workflow's plan job (dispatched
  # from main, no environment, so sub carries the ref).
  ci_plan_allowed_subs = [
    "${local.github_repo_sub_prefix}:pull_request",
    "${local.github_repo_sub_prefix}:ref:refs/heads/main",
  ]

  # Apply role: the production-apply environment only. With an environment,
  # sub carries the environment name instead of the ref, so this trust
  # cannot see the branch. The environment's deployment-branch policy
  # (main only) is what keeps other branches out. Checked 11 Nov 2026.
  ci_apply_allowed_subs = [
    "${local.github_repo_sub_prefix}:environment:production-apply",
  ]

  # Saved plans from the apply workflow. Keyed by run ID and attempt.
  # Lifecycle expiry in bootstrap/main.tf. Never a GitHub artifact: a plan
  # file holds resolved values in plaintext and this repo is public.
  plans_prefix_arn = "${local.state_bucket_arn}/plans/*"

  # use_lockfile = true writes the lock beside the state as <key>.tflock.
  state_lock_arn = "${local.state_bucket_arn}/environments/*/terraform.tfstate.tflock"
}

# ---------------------------------------------------------------
# Trust policies: WHO can assume each role.
# ---------------------------------------------------------------

data "aws_iam_policy_document" "ci_plan_trust" {
  statement {
    sid     = "GitHubActionsOIDCPlan"
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
      values   = local.ci_plan_allowed_subs
    }
  }
}

data "aws_iam_policy_document" "ci_apply_trust" {
  statement {
    sid     = "GitHubActionsOIDCApply"
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
      values   = local.ci_apply_allowed_subs
    }
  }
}

# ---------------------------------------------------------------
# ci_read: reads only. Shared by both roles.
# ---------------------------------------------------------------

data "aws_iam_policy_document" "ci_read" {
  # checkov:skip=CKV_AWS_108:S3 reads are scoped to environment state. SSM reads public AMI parameters. No unbounded data access.
  # checkov:skip=CKV_AWS_356:ec2:Describe*, logs describe and SSM parameter reads have no resource-level permissions. Read-only.

  statement {
    sid       = "EC2Read"
    effect    = "Allow"
    actions   = ["ec2:Describe*"]
    resources = ["*"]
  }

  # Dev reads the SSM instance profile owned by bootstrap.
  statement {
    sid       = "IAMReadInstanceProfile"
    effect    = "Allow"
    actions   = ["iam:GetInstanceProfile"]
    resources = [aws_iam_instance_profile.ec2_ssm.arn]
  }

  statement {
    sid       = "S3StateBucketList"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [local.state_bucket_arn]
  }

  # Covers state and the lock object (reading the lock shows who holds it).
  statement {
    sid       = "S3EnvironmentStateRead"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${local.state_bucket_arn}/environments/*"]
  }

  # Bootstrap state governs these roles. Neither role may touch it.
  statement {
    sid       = "DenyBootstrapState"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = ["${local.state_bucket_arn}/bootstrap/*"]
  }

  statement {
    sid    = "EventBridgeK3sRulesRead"
    effect = "Allow"
    actions = [
      "events:DescribeRule",
      "events:ListTargetsByRule",
      "events:ListTagsForResource",
    ]
    resources = ["arn:aws:events:${local.region}:${local.account_id}:rule/${local.k3s_prefix}-*"]
  }

  statement {
    sid       = "LogsK3sSpotEventGroupsRead"
    effect    = "Allow"
    actions   = ["logs:ListTagsForResource"]
    resources = ["arn:aws:logs:${local.region}:${local.account_id}:log-group:/aws/events/${local.k3s_prefix}-*"]
  }

  # No resource-level permissions on these two in AWS.
  statement {
    sid    = "LogsDescribe"
    effect = "Allow"
    actions = [
      "logs:DescribeResourcePolicies",
      "logs:DescribeLogGroups",
    ]
    resources = ["*"]
  }

  # AMI lookup through the AL2023 public SSM parameter.
  statement {
    sid    = "SSMParameterRead"
    effect = "Allow"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "STSIdentity"
    effect    = "Allow"
    actions   = ["sts:GetCallerIdentity"]
    resources = ["*"]
  }
}

# ---------------------------------------------------------------
# ci_plan: ci_read plus the two writes a plan job needs.
# ---------------------------------------------------------------

data "aws_iam_policy_document" "ci_plan" {
  source_policy_documents = [data.aws_iam_policy_document.ci_read.json]

  # The state lock. Replaces -lock=false: a plan that reads state while an
  # apply is writing it shows a wrong diff. Lock object only, never state.
  statement {
    sid    = "S3StateLockWrite"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = [local.state_lock_arn]
  }

  # The apply workflow's plan job uploads the saved plan here. PR plans
  # also hold this permission (same role), so the apply job verifies the
  # plan's SHA-256 from the plan job's output before applying.
  statement {
    sid       = "S3PlansWrite"
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = [local.plans_prefix_arn]
  }
}

# ---------------------------------------------------------------
# ci_write: every mutating action. Apply role only.
# ---------------------------------------------------------------

data "aws_iam_policy_document" "ci_write" {
  # checkov:skip=CKV_AWS_109:logs:PutResourcePolicy has no resource-level permissions. Permission boundary caps privilege.
  # checkov:skip=CKV_AWS_110:iam:PassRole is scoped to the EC2 SSM role passed to EC2 only. Boundary carries the same exception.
  # checkov:skip=CKV_AWS_111:EC2 create actions do not support resource-level restrictions. Permission boundary is the constraint.
  # checkov:skip=CKV_AWS_356:EC2 actions cannot be scoped to resources at creation time. S3 is scoped to the state bucket.

  statement {
    sid    = "EC2VPCWrite"
    effect = "Allow"
    actions = [
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

      # Instances (NAT instance, K3s server)
      "ec2:RunInstances",
      "ec2:TerminateInstances",
      "ec2:ModifyInstanceAttribute",

      # Launch templates (K3s server)
      "ec2:CreateLaunchTemplate",
      "ec2:CreateLaunchTemplateVersion",
      "ec2:ModifyLaunchTemplate",
      "ec2:DeleteLaunchTemplate",
      "ec2:DeleteLaunchTemplateVersions",

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

  # Launching EC2 with the SSM instance profile. That role, to EC2 only.
  statement {
    sid       = "PassEc2SsmRoleToEc2"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = [local.ec2_ssm_role_arn]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ec2.amazonaws.com"]
    }
  }

  # State write and the lock. GetObject comes from ci_read.
  statement {
    sid    = "S3EnvironmentStateWrite"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = ["${local.state_bucket_arn}/environments/*"]
  }

  # The apply job downloads the saved plan the reviewer approved.
  statement {
    sid       = "S3PlansRead"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = [local.plans_prefix_arn]
  }

  statement {
    sid    = "EventBridgeK3sRulesWrite"
    effect = "Allow"
    actions = [
      "events:PutRule",
      "events:DeleteRule",
      "events:PutTargets",
      "events:RemoveTargets",
      "events:TagResource",
      "events:UntagResource",
    ]
    resources = ["arn:aws:events:${local.region}:${local.account_id}:rule/${local.k3s_prefix}-*"]
  }

  statement {
    sid    = "LogsK3sSpotEventGroupsWrite"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:DeleteLogGroup",
      "logs:PutRetentionPolicy",
      "logs:DeleteRetentionPolicy",
      "logs:TagResource",
      "logs:UntagResource",
    ]
    resources = ["arn:aws:logs:${local.region}:${local.account_id}:log-group:/aws/events/${local.k3s_prefix}-*"]
  }

  statement {
    sid    = "LogsResourcePolicyWrite"
    effect = "Allow"
    actions = [
      "logs:PutResourcePolicy",
      "logs:DeleteResourcePolicy",
    ]
    resources = ["*"]
  }
}

data "aws_iam_policy_document" "ci_apply" {
  source_policy_documents = [
    data.aws_iam_policy_document.ci_read.json,
    data.aws_iam_policy_document.ci_write.json,
  ]
}

# ---------------------------------------------------------------
# Roles, policies, attachments. Both bounded by the same boundary.
# ---------------------------------------------------------------

resource "aws_iam_role" "ci_plan" {
  name                 = "platform10-ci-plan"
  description          = "GitHub Actions plan role. Read-only plus state lock and saved-plan upload."
  assume_role_policy   = data.aws_iam_policy_document.ci_plan_trust.json
  permissions_boundary = aws_iam_policy.permission_boundary.arn
  max_session_duration = 3600

  tags = {
    Name = "${var.name_prefix}-ci-plan-role"
  }
}

resource "aws_iam_policy" "ci_plan" {
  name   = "platform10-ci-plan"
  policy = data.aws_iam_policy_document.ci_plan.json

  tags = {
    Name = "${var.name_prefix}-ci-plan-policy"
  }
}

resource "aws_iam_role_policy_attachment" "ci_plan" {
  role       = aws_iam_role.ci_plan.name
  policy_arn = aws_iam_policy.ci_plan.arn
}

resource "aws_iam_role" "ci_apply" {
  name                 = "platform10-ci-apply"
  description          = "GitHub Actions apply role. Write access, production-apply environment only."
  assume_role_policy   = data.aws_iam_policy_document.ci_apply_trust.json
  permissions_boundary = aws_iam_policy.permission_boundary.arn
  max_session_duration = 3600

  tags = {
    Name = "${var.name_prefix}-ci-apply-role"
  }
}

resource "aws_iam_policy" "ci_apply" {
  name   = "platform10-ci-apply"
  policy = data.aws_iam_policy_document.ci_apply.json

  tags = {
    Name = "${var.name_prefix}-ci-apply-policy"
  }
}

resource "aws_iam_role_policy_attachment" "ci_apply" {
  role       = aws_iam_role.ci_apply.name
  policy_arn = aws_iam_policy.ci_apply.arn
}
