# Service-linked role that EC2 uses to launch and manage Spot instances.
# It is account-wide and only needs to exist once.
# It lives in bootstrap because environments/dev is destroyed every session.
resource "aws_iam_service_linked_role" "ec2_spot" {
  aws_service_name = "spot.amazonaws.com"
  description      = "Lets EC2 launch and manage Spot instances for platform10"
}
