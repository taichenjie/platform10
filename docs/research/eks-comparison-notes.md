# EKS comparison notes

**Written:** 29 Oct 2026 (M5).
**Status:** Research notes. Input to ADR-006 (K3s vs EKS, CNI posture and ownership boundary) in M6. The M11 EKS weekend tests the claims here on a real cluster.

## Why I wrote this

I run K3s on EC2 instead of Amazon EKS. An interviewer will ask why, and ADR-006 needs a fair comparison, not just "EKS costs more". These notes record what EKS would change in cost, ownership, networking, versions and pod permissions.

## What EKS is

Amazon EKS runs the Kubernetes control plane for me. AWS operates the API server and etcd across several availability zones, patches them, and backs them up. I still run the worker nodes, unless I use Fargate or EKS Auto Mode, where AWS manages those too.

## Who owns what

| Layer | K3s on EC2 (today) | EKS |
|---|---|---|
| API server, scheduler, controllers | Me. One server node | AWS. Spread across AZs |
| Datastore (cluster state) | Me. SQLite now, embedded etcd with S3 snapshots in M9 | AWS. Managed etcd, backed up by AWS |
| Control plane high availability | None until 3 servers | Included |
| Kubernetes version upgrades | Me. I choose when, and nothing forces me | Me, but AWS ends standard support after 14 months and then charges more |
| Worker node OS and patching | Me | Me (managed node groups help), or AWS with Auto Mode or Fargate |
| Pod networking (CNI) | Flannel overlay | Amazon VPC CNI. Pods get real VPC IP addresses |
| NetworkPolicy enforcement | K3s embedded controller, on by default | VPC CNI network policy agent, off until enabled |
| Ingress | Traefik, bundled with K3s | AWS Load Balancer Controller, or my own ingress controller |
| AWS permissions for pods | Instance role only. IMDS hop limit 1 blocks pods from it | Per-pod IAM roles with EKS Pod Identity or IRSA |

## Cost

Prices are from the AWS EKS pricing page on 29 Oct 2026. The page does not list region-specific EKS rates, so I will confirm Singapore in the AWS Pricing Calculator before ADR-006.

| Item | Price | Per 3-hour session | 24/7 for a month |
|---|---|---|---|
| EKS control plane, standard support | $0.10/hr | $0.30 | about $73 |
| EKS control plane, extended support | $0.60/hr | $1.80 | about $438 |
| K3s control plane | $0. It runs on my own node | $0 | $0 |
| EKS Auto Mode | A management fee per instance on top of EC2 | | |
| Fargate | Per vCPU and GB of memory, per second | | |

Worker nodes cost the same either way, because they are EC2 instances. The control plane fee alone is more than seven times my $10 monthly budget. That is why K3s.

## Versions

EKS gives each Kubernetes minor version 14 months of standard support, then 12 months of extended support at six times the cluster price. Extended support is on by default.

| EKS version | Released on EKS | End of standard support |
|---|---|---|
| 1.37 | 1 Oct 2026 | 1 Dec 2027 |
| 1.36 | 2 Jun 2026 | 2 Aug 2027 |
| 1.35 | 27 Jan 2026 | 27 Mar 2027 |
| 1.34 | 2 Oct 2025 | 2 Dec 2026 |

My K3s pin is v1.35.9. On EKS the same minor version would be in standard support until 27 Mar 2027. On K3s nothing forces an upgrade, so keeping up is my own discipline. That is why the M9 upgrade demo exists.

## Networking

**Pod IPs and the pod limit per node.** VPC CNI gives each pod a real IP from the VPC subnet. A node can only hold as many pods as its network interfaces have IPs. AWS's formula is ENIs × (IPs per ENI − 1) + 2.

| Instance | ENIs | IPs per ENI | Max pods on EKS (default) |
|---|---|---|---|
| t4g.small | 3 | 4 | 11 |
| t4g.medium | 3 | 6 | 17 |

My planned stack (ArgoCD, Kyverno, Prometheus, Grafana, cert-manager, the EBS CSI driver, Postgres, the API and the system pods) is well over 17 pods. On EKS I would need prefix delegation, which assigns IP blocks to each interface and raises the limit. K3s does not have this limit, because Flannel gives pods addresses from its own overlay network.

**NetworkPolicy.** VPC CNI enforces standard NetworkPolicy from version 1.14, once `enableNetworkPolicy` is set to true. An eBPF agent runs inside the `aws-node` DaemonSet. Two details differ from K3s.

- In the default "standard" mode, a new pod starts with traffic allowed until its policies are applied. "Strict" mode starts every pod at deny-all, so even CoreDNS needs an explicit allow.
- Policy decisions can be exported to a log collector. On K3s, blocked connections are rejected with no log.

## Pod permissions

On K3s, every pod shares one EC2 instance role, so I block pods from it with an IMDS hop limit of 1. Pods currently have no AWS credentials at all. On EKS, Pod Identity gives each workload its own IAM role with only the permissions it needs.

This matters in M8. The EBS CSI driver is a pod that needs AWS permissions to create volumes. On K3s it will need host networking, a hop limit of 2, or a self-hosted OIDC setup. On EKS it gets its own role.

## What K3s teaches that EKS hides

- Running and backing up the datastore myself (etcd snapshots and restores in M9).
- How nodes join a cluster, with tokens.
- Which component enforces NetworkPolicy, and how to prove it works.
- Upgrades with no provider deadline, which take discipline.

These are the skills EKS takes off my hands. Learning them on K3s first makes EKS easier to reason about.

## When EKS is the right choice

- A team needs a highly available control plane without running 3 servers and etcd themselves.
- Workloads need per-pod IAM roles, which EKS provides natively.
- The budget covers about $73 a month per cluster, and someone owns staying within standard support.
- Compliance needs a managed, AWS-patched control plane.

None of these apply to a solo build under $10 a month.

## Questions for the M11 EKS weekend

- How long cluster create and delete take, and what that does to my apply and destroy session pattern.
- How many pods my stack needs on EKS, and whether prefix delegation covers it on a t4g.medium.
- Whether my NetworkPolicy negative test gives the same result on VPC CNI in standard and strict mode.
- The real Singapore cost of the weekend, compared with the pricing page.

## Sources

- Amazon EKS pricing: https://aws.amazon.com/eks/pricing/
- EKS Kubernetes version lifecycle: https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html
- VPC CNI network policy setup: https://docs.aws.amazon.com/eks/latest/userguide/cni-network-policy-configure.html
- EKS AMI max pods formula and instance data: https://github.com/awslabs/amazon-eks-ami (nodeadm/internal/kubelet/eni_max_pods.go and instance-info.jsonl)
