# ---------------------------------------------------------------------------
# Permission boundary policy.
#
# This document is the CEILING — the maximum permissions any bounded
# principal can ever effectively have. It does not grant anything on its
# own; it caps whatever the principal's identity policy tries to grant.
#
# Effective permissions = (identity policy allows) ∩ (boundary allows)
#                       − (any explicit deny in either)
#
# An explicit Deny in the boundary wins over any Allow in the identity
# policy. This is how privilege escalation is made structurally
# impossible, even if a future identity policy is misconfigured.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "permission_boundary" {
  # Baseline: the ceiling is whatever the identity policy grants.
  # The explicit Deny statements below carve out the dangerous parts.
  statement {
    sid       = "AllowBaseline"
    effect    = "Allow"
    actions   = ["*"]
    resources = ["*"]
  }

  # Block the IAM actions that enable privilege escalation. A bounded
  # principal can never create new IAM principals, attach policies to
  # itself or others, or modify access keys — even if its identity
  # policy somehow allows it.
  statement {
    sid    = "DenyIAMPrivilegeEscalation"
    effect = "Deny"
    actions = [
      "iam:CreatePolicy",
      "iam:CreatePolicyVersion",
      "iam:SetDefaultPolicyVersion",
      "iam:DeletePolicyVersion",
      "iam:AttachUserPolicy",
      "iam:DetachUserPolicy",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:AttachGroupPolicy",
      "iam:DetachGroupPolicy",
      "iam:PutUserPolicy",
      "iam:PutRolePolicy",
      "iam:PutGroupPolicy",
      "iam:DeleteUserPolicy",
      "iam:DeleteRolePolicy",
      "iam:DeleteGroupPolicy",
      "iam:CreateUser",
      "iam:CreateRole",
      "iam:CreateAccessKey",
      "iam:UpdateAccessKey",
      "iam:CreateLoginProfile",
      "iam:UpdateLoginProfile",
      "iam:PassRole"
    ]
    resources = ["*"]
  }

  # Protect the boundary itself. A bounded principal cannot remove its
  # own boundary or attach a weaker boundary to other principals.
  # Without this, the ceiling could be lifted from below — meaningless.
  statement {
    sid    = "ProtectPermissionBoundary"
    effect = "Deny"
    actions = [
      "iam:DeleteUserPermissionsBoundary",
      "iam:DeleteRolePermissionsBoundary",
      "iam:PutUserPermissionsBoundary",
      "iam:PutRolePermissionsBoundary"
    ]
    resources = ["*"]
  }

  # Block destructive account-, org-, and KMS-level operations. These
  # require a level of intent that no service role in this project
  # should ever have.
  statement {
    sid    = "DenyAccountAndDestructiveOps"
    effect = "Deny"
    actions = [
      "organizations:*",
      "account:*",
      "kms:ScheduleKeyDeletion",
      "kms:DisableKey",
      "kms:DeleteAlias"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "permission_boundary" {
  name        = "platform10-dev-permission-boundary"
  description = "Permission boundary for all non-root principals in dev. Caps the maximum permissions any bounded role can effectively have, regardless of attached identity policies."
  policy      = data.aws_iam_policy_document.permission_boundary.json

  tags = {
    Name = "platform10-dev-permission-boundary"
  }
}

# Expose the boundary ARN so other Terraform code (Task 5's SSM role)
# can attach it to roles it creates.
output "permission_boundary_arn" {
  description = "ARN of the platform10 permission boundary. Attach this to every non-root role created in this environment."
  value       = aws_iam_policy.permission_boundary.arn
}

# ---------------------------------------------------------------------------
# IAM role for EC2 instances that need SSM Session Manager access.
#
# Trust policy: only the EC2 service can assume this role. No human or
# external principal can.
#
# Bounded by the platform10 permission boundary — even if a broader
# policy is later attached, the bounded role cannot exceed the ceiling.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2_ssm" {
  name                 = "platform10-dev-ec2-ssm-role"
  description          = "Allows EC2 instances to be reached via SSM Session Manager. Bounded by the platform10 permission boundary."
  assume_role_policy   = data.aws_iam_policy_document.ec2_assume_role.json
  permissions_boundary = aws_iam_policy.permission_boundary.arn

  tags = {
    Name = "platform10-dev-ec2-ssm-role"
  }
}

# Attach the AWS-managed policy that gives the SSM Agent the permissions
# it needs to register, receive sessions, and send logs. Maintained by AWS.
resource "aws_iam_role_policy_attachment" "ec2_ssm_core" {
  role       = aws_iam_role.ec2_ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Instance profile: the wrapper that lets an EC2 instance carry this role.
# EC2 cannot use an IAM role directly — only an instance profile.
resource "aws_iam_instance_profile" "ec2_ssm" {
  name = "platform10-dev-ec2-ssm-profile"
  role = aws_iam_role.ec2_ssm.name

  tags = {
    Name = "platform10-dev-ec2-ssm-profile"
  }
}

output "ec2_ssm_instance_profile_name" {
  description = "Name of the EC2 SSM instance profile. Pass this to any EC2 instance that should be reachable via SSM."
  value       = aws_iam_instance_profile.ec2_ssm.name
}
