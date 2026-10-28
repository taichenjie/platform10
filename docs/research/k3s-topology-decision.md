# K3s cluster topology decision

**First written:** 21 Oct 2026 (M5). **Updated:** 28 Oct 2026 (M5).
**Status:** Decided in M5. ADR-006 records it formally in M6.
**Decision:** one t4g.medium Spot server for M6 to M8. A t4g.small Spot agent joins in M9.

## The question

My CNI posture memo found that a t4g.small (2 GiB) sits exactly at the K3s server minimum before any workload runs. To plan for future workloads like ArgoCD, Postgres and Prometheus, I measured the idle node in M5 and used that number to decide the cluster layout for M6 onwards.

## Terms used here

| Term | Meaning |
|---|---|
| K3s | A lightweight Kubernetes distribution packaged as one binary. I run it on EC2 instead of EKS, whose control plane alone costs about $73 a month. |
| Server node | Runs the control plane (API server, scheduler, controllers, datastore). In K3s it also runs workloads. |
| Agent node | A K3s worker. It runs the kubelet and containers but no control plane, so it needs less memory. It joins with a token from the server. |
| Datastore | Where K3s keeps cluster state. A single server uses SQLite by default. Embedded etcd is the alternative and supports snapshots to S3. It is also what K3s needs for a highly available control plane with 3 or more servers. |
| Spot | Spare EC2 capacity at about half price. AWS can reclaim it with a 2 minute warning, which terminates the node. |
| Smoke test | A short live test before building further. In M5 it was one apply, then SSM access, node Ready, DNS resolution (which needs no security group rule, since security groups do not filter the Amazon resolver) and internet egress through the NAT, a NetworkPolicy check, and idle memory and disk, then a destroy. |

## What I measured

A t4g.small Spot node, K3s v1.35.9+k3s1 on SQLite, nothing deployed. Two samples a minute apart, after the node had been idle for two minutes.

| Measure | Sample 1 | Sample 2 |
|---|---|---|
| Usable RAM (`free -m` total) | 1840 MiB | 1840 MiB |
| Available | 902 MiB | 866 MiB |
| Node memory as the scheduler sees it (`kubectl top node`) | 1020 MiB, 55% | 1041 MiB, 56% |
| `k3s-server` process RSS | about 607 MiB | about 624 MiB |
| containerd RSS | about 147 MiB | about 147 MiB |
| K3s system pods (Traefik, metrics-server, CoreDNS, local-path) | about 58 MiB | about 59 MiB |
| Root disk used | 3.0 of 20 GB | 3.0 of 20 GB |

About 870 to 900 MiB is left for workloads on an idle t4g.small.

## What has to fit

Everything M6 to M9 adds to the cluster. The memory figures are rough estimates. I will replace each one with a measured number when the component lands.

| Component | Month | Why I am adding it | Why this tool | Estimate |
|---|---|---|---|---|
| ArgoCD | M6 | GitOps. The cluster pulls its state from git and reverts manual changes, so a rebuilt cluster restores itself. | Widely used, and its UI shows drift and self-heal clearly. | about 400 MB |
| Kyverno | M7 | Policy as code. It rejects manifests that break my rules, such as running as root or missing resource limits. | Policies are YAML like the manifests they check, not a separate language like OPA's Rego. | about 200 MB |
| Python API (FastAPI) | M7 to M8 | The workload the platform exists to run. | A common stack that hiring teams recognise. It replaced the RPC node in M4, which did not fit a 2 GB node. | about 100 MB |
| Postgres | M8 | The API's database. It makes the platform stateful, so I have to prove backups and restores (ADR-009). | The most common open-source relational database. | about 200 MB |
| EBS CSI driver | M8 | Creates the EBS volume Postgres stores its data on. | The AWS driver for EBS volumes in Kubernetes. | about 100 MB |
| Prometheus | M8 | Metrics and alerting. Feeds the SLOs in M10. | The standard metrics stack for Kubernetes. | about 400 MB |
| Grafana | M8 | Dashboards for the API and Postgres. | Pairs with Prometheus. | about 150 MB |
| cert-manager | M8 | Issues TLS certificates for the API's ingress from a private CA. | The standard certificate controller for Kubernetes. | about 100 MB |
| Embedded etcd, replacing SQLite | M9 | Cluster state survives a Spot interruption through snapshots to S3. | Built into K3s. K3s's own profiling measured it about 10 MB above SQLite (1606 vs 1596 MB). | about 10 MB |
| **Total** | | | | **about 1.6 GiB** |

M10 adds Loki, the OTel collector and k6 load tests. They are not counted here. Even without them, one t4g.small cannot hold this stack.

## Prices on 21 Oct 2026, ap-southeast-1a

| Instance | vCPU and RAM | Spot USD/hr | On-Demand USD/hr |
|---|---|---|---|
| t4g.small | 2 vCPU, 2 GiB | 0.0093 | 0.0212 |
| t4g.medium | 2 vCPU, 4 GiB | 0.0201 | 0.0424 |

Spot prices came from `aws ec2 describe-spot-price-history`. On-Demand prices came from the Price List API, which does not carry Spot prices. I use ap-southeast-1a because the node is pinned there, where the M8 Postgres volume will live.

## The options

| | 2x t4g.small (server and agent) | 1x t4g.medium (server) |
|---|---|---|
| Spot cost per hour | 0.0186 | 0.0201 |
| Cost per 3-hour session | about $0.06 | about $0.06 |
| 24/7 Spot cost per month | about $13.58, plus a second 20 GiB root volume at about $1.92 | about $14.67 |
| Memory for workloads | about 870 MiB on the server plus about 1.2 GiB on the agent, so about 2.1 GiB split across two nodes | about 2.8 GiB in one pool |
| Left after the planned stack (about 1.6 GiB) | about 0.5 GiB, split across two nodes | about 1.2 GiB |
| Multi-node behaviour | Yes. Node join, scheduling across nodes, draining | No |
| Spot interruption | Losing the agent leaves the control plane up | Losing the node takes the whole cluster down |
| Change needed | A second launch template, agent user data and a join token | One variable, `instance_type` |

The agent estimate uses the K3s agent figure of about 275 MB from K3s's resource profiling, plus containerd and the OS. It is an estimate.

## Decision

I am moving the server to a t4g.medium for M6 to M8.

Memory decides this, not price. The two options cost within a cent per session of each other, and the same On-Demand. The medium gives about 2.8 GiB in one pool against about 2.1 GiB split across two nodes. A pod can only use the free memory on the node it lands on, so the split matters for large components like Prometheus and ArgoCD. It is also one variable to change, so M6 starts on ArgoCD instead of agent setup.

A t4g.small agent joins in M9. The node rotation demo needs a second node to move workloads onto, so the agent arrives when it has a job to do.

## What I am accepting

- Until M9 the cluster is one node. A Spot interruption takes everything down until the next apply. Dev is rebuilt every session anyway, and once ArgoCD is in, workloads come back from git.
- The workload figures are estimates. If ArgoCD alone lands well above 400 MB in M6, I will revisit this before Kyverno goes in.
- Running the medium 24/7 costs more than my $10 a month rule. That only matters for the always-on windows planned in Q4, and I decide how to handle them at M9 close with measured memory data.

## What changes elsewhere

- **M6.** Set `instance_type = "t4g.medium"` for the k3s-cluster module in dev. The Infracost delta and the Spot price at the time go in that PR.
- **M9.** A t4g.small agent joins with its own agent token. The datastore moves from SQLite to embedded etcd with snapshots to S3. Both tokens live in SSM Parameter Store. The node security group already allows traffic between nodes in the same group, so no new firewall rules are needed.

## When I would change this

- Measured workloads go past about 2.5 GiB on the medium. Then the M9 agent comes forward, or the server moves up a size.
- t4g.medium Spot capacity in ap-southeast-1a becomes unreliable. Then the mixed-instance Auto Scaling group comes out of the backlog.
- I need the control plane to survive a node loss before M9. Then the two-node layout comes forward.
