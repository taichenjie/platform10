# k3s-cluster

A single-node K3s server on an EC2 Spot instance in a private subnet. I use it as the Kubernetes base for Platform 10. The dev stack applies it at the start of each session and destroys it at the end.

## What it creates

- An EC2 instance launched from a launch template, on t4g.small Graviton Spot by default
- A security group for K3s nodes
- An EventBridge rule that records Spot rebalance and interruption warnings for this instance in a CloudWatch log group

The user data installs a pinned K3s release as a server, then waits for the node to report Ready.

## Security posture

- No SSH and no public IP. I reach the node only through SSM Session Manager, using an instance profile from the bootstrap layer.
- IMDSv2 is required with a hop limit of 1, so pods cannot use the node's IAM role.
- The root volume is encrypted gp3.
- Ingress is allowed only from other nodes in the same security group. Egress is 443 to anywhere plus all traffic to the same group. Security groups do not filter the Amazon DNS resolver, IMDS or time sync, so they need no rules.
- K3s runs with secrets encryption on and the kubeconfig set to mode 0600.
- The embedded NetworkPolicy controller stays on. I never set `--disable-network-policy`, because without it policies are accepted but not enforced.
- The installer is downloaded from the K3s release tag, not from get.k3s.io, so a rebuild always runs the same script.

## Known trade-offs

- **Spot plus SQLite means state loss.** K3s uses SQLite on a single server. A Spot interruption terminates the instance and deletes the root volume, and the cluster state goes with it. I accept this because dev is rebuilt every session and workloads will be redeployed from git. The fix is embedded etcd with snapshots to S3 and a stable server token. That is planned for M8, and it costs extra memory on the node.
- **One node, no high availability.** The control plane and workloads share one instance.
- **Boot depends on NAT egress.** The installer needs internet access through the NAT instance. If egress is not ready within the user data's retry window, the install fails and only a new instance retries it. `scripts/dev-apply.sh` detects this and fails clearly. A golden AMI built with Packer, with Renovate proposing version bumps, is planned for M9 and removes the install from boot.
- **The K3s version is one minor behind on purpose.** It sets up a real upgrade and node rotation demo in M9. It is not an unpatched cluster by accident.
- **Spot event history is lost on destroy.** The log group lives in the dev stack, so each destroy deletes it.
- **Checkov skips on `aws_instance`.** Checkov does not follow settings into the launch template, so the instance carries skips that name the launch template setting each check relies on.

## Usage

~~~hcl
module "k3s_cluster" {
  source = "../../modules/k3s-cluster"

  name_prefix           = var.vpc_name
  vpc_id                = module.vpc.vpc_id
  subnet_id             = module.vpc.private_subnet_ids["private-az1"]
  instance_profile_name = data.aws_iam_instance_profile.ec2_ssm.name
}
~~~

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.15.5 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.67.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_cloudwatch_event_rule.spot_interruption](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_rule) | resource |
| [aws_cloudwatch_event_target.spot_to_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_target) | resource |
| [aws_cloudwatch_log_group.spot_events](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_cloudwatch_log_resource_policy.events_to_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_resource_policy) | resource |
| [aws_instance.server](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/instance) | resource |
| [aws_launch_template.server](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/launch_template) | resource |
| [aws_security_group.node](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_vpc_security_group_egress_rule.node_https](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_egress_rule.node_to_nodes](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.node_from_nodes](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [aws_iam_policy_document.events_to_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_ssm_parameter.al2023_arm64](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ssm_parameter) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_instance_profile_name"></a> [instance\_profile\_name](#input\_instance\_profile\_name) | Name of the EC2 SSM instance profile created in bootstrap. | `string` | n/a | yes |
| <a name="input_instance_type"></a> [instance\_type](#input\_instance\_type) | EC2 instance type. Must be ARM (Graviton) to match the arm64 AMI. | `string` | `"t4g.small"` | no |
| <a name="input_k3s_version"></a> [k3s\_version](#input\_k3s\_version) | Exact K3s release to install, e.g. v1.35.9+k3s1. | `string` | `"v1.35.9+k3s1"` | no |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Prefix for all resource names, e.g. platform10-dev. | `string` | n/a | yes |
| <a name="input_root_volume_size_gib"></a> [root\_volume\_size\_gib](#input\_root\_volume\_size\_gib) | Root volume size in GiB. Holds the OS, K3s and container images. Confirmed by the M5 smoke test. | `number` | `20` | no |
| <a name="input_subnet_id"></a> [subnet\_id](#input\_subnet\_id) | ID of the PRIVATE subnet for the node. The node never gets a public IP. | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Extra tags merged onto every resource. Provider default\_tags still apply. | `map(string)` | `{}` | no |
| <a name="input_use_spot"></a> [use\_spot](#input\_use\_spot) | Launch as Spot (true) or On-Demand (false). Set false only if Spot capacity is unavailable. | `bool` | `true` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | ID of the VPC the node runs in. Used by the node security group. | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_instance_id"></a> [instance\_id](#output\_instance\_id) | ID of the K3s server instance. Used by the apply script to wait for SSM. |
| <a name="output_k3s_version"></a> [k3s\_version](#output\_k3s\_version) | K3s release installed on the node. |
| <a name="output_launch_template_id"></a> [launch\_template\_id](#output\_launch\_template\_id) | ID of the K3s server launch template. |
| <a name="output_launch_template_version"></a> [launch\_template\_version](#output\_launch\_template\_version) | Launch template version the running node was built from. |
| <a name="output_private_ip"></a> [private\_ip](#output\_private\_ip) | Private IP of the K3s server. |
| <a name="output_security_group_id"></a> [security\_group\_id](#output\_security\_group\_id) | ID of the node security group. A second node in M6 joins this group. |
| <a name="output_spot_events_log_group"></a> [spot\_events\_log\_group](#output\_spot\_events\_log\_group) | CloudWatch log group that records Spot signals for the K3s server. |
<!-- END_TF_DOCS -->
