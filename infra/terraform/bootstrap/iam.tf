# Account-level IAM. Lives in bootstrap because environments/dev is
# destroyed every session, and CI cannot assume a role that does not exist.
# Applied locally as cj-admin. The permission boundary blocks bounded
# roles from creating roles, so CI cannot manage this layer.

# Permission boundary, GitHub OIDC provider, CI role, EC2 SSM role and
# instance profile. Moved here from environments/dev on 3 Oct 2026.
# name_prefix kept as platform10-dev so role and profile names are unchanged.
module "iam" {
  source      = "../modules/iam"
  name_prefix = "platform10-dev"
}

# Service-linked role that EC2 uses to launch and manage Spot instances.
# It is account-wide and only needs to exist once.
resource "aws_iam_service_linked_role" "ec2_spot" {
  aws_service_name = "spot.amazonaws.com"
  description      = "Lets EC2 launch and manage Spot instances for platform10"
}
