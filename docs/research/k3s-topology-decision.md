# K3s cluster topology decision (M5)

**Date:** 21 Oct 2026
**Decision:** a single t4g.medium Spot server for M6 to M8. A t4g.small Spot agent joins in M9.
**Inputs:** the M5 smoke test on 21 Oct 2026, and live Spot prices for ap-southeast-1a.
**Recorded in:** this note is the evidence. The decision itself goes into ADR-006 (K3s vs EKS, CNI posture and ownership boundary) in M6.

## Background

These terms come up throughout this note.

| Term | What it means here |
|---|---|
| K3s | A lightweight Kubernetes distribution packaged as a single binary. I run it on EC2 instead of paying for EKS, which costs about $73 a month for the control plane alone. |
| Server node | A K3s node that runs the control plane (API server, scheduler, controllers and the datastore). In K3s a server also runs workloads unless I stop it. |
| Agent node | A K3s worker. It runs the kubelet and containers but no control plane, so it uses less memory than a server. It joins the cluster using a token from the server. |
| Datastore | Where K3s keeps cluster state, meaning every Deployment, Service and Secret. A single K3s server uses SQLite by default. Embedded etcd is the alternative, and it supports snapshots to S3. |
| Spot | Spare EC2 capacity sold at about half price. AWS can take it back with a 2 minute warning, which terminates my node. |
| CNI | The Container Network Interface plugin that gives pods their IPs and connects them. K3s ships Flannel, which does not enforce NetworkPolicy. K3s adds a separate embedded controller that does. |
| CNI posture memo | `docs/research/cni-posture-memo.md`, written in M4. It compared the embedded NetworkPolicy controller with Cilium. It chose the embedded controller because Cilium's agent would take a large share of a 2 GB node. It also found that a t4g.small sits exactly at the K3s server minimum of 2 GB. |
| Smoke test | A short live test that proves the basics work before building on them. In M5 it was one apply of the k3s-cluster module, checking SSM access, node Ready, DNS and NAT egress, NetworkPolicy enforcement, and idle memory and disk, then a destroy. |

## Why this needed deciding

The CNI posture memo showed that a t4g.small has no spare memory on paper. I did not want to find out in M8, when Prometheus runs the node out of memory. So I agreed to measure the idle node in M5 and let that number choose the layout for M6 onwards.

## What I measured

The node was a t4g.small Spot instance running K3s v1.35.9+k3s1 on SQLite, with nothing deployed. I took two samples a minute apart, after deleting the test namespace and waiting two minutes.

| Measure | Sample 1 | Sample 2 |
|---|---|---|
| Usable RAM (`free -m` total) | 1840 MiB | 1840 MiB |
| Available | 902 MiB | 866 MiB |
| Node memory as the scheduler sees it (`kubectl top node`) | 1020 MiB, 55% | 1041 MiB, 56% |
| `k3s-server` process RSS | about 607 MiB | about 624 MiB |
| containerd RSS | about 147 MiB | about 147 MiB |
| K3s system pods (Traefik, metrics-server, CoreDNS, local-path) | about 58 MiB | about 59 MiB |
| Root disk used | 3.0 of 20 GB | 3.0 of 20 GB |

The `k3s-server` process is the biggest cost. It holds the API server, scheduler, controllers, kubelet and SQLite in one process. The system pods ship with K3s and are small.

About 870 to 900 MiB is left for my own workloads on an idle t4g.small.

## What has to fit, and why each piece is coming

Each component below has a job in the roadmap. The memory figures are rough working-set estimates, not measurements. I will replace them with real numbers as each one lands.

| Component | Month | Why I am adding it | Why this tool | Estimate |
|---|---|---|---|---|
| ArgoCD | M6 | GitOps. The cluster pulls its desired state from git and reverts manual changes, so a destroyed cluster rebuilds itself from the repo. | Widely used for GitOps, and its UI shows drift and self-heal clearly for the Article 3 capture. | about 400 MB |
| Kyverno | M7 | Policy as code. It rejects manifests that break my rules, such as containers running as root or missing resource limits, before they reach the cluster. | Policies are written in YAML like the manifests they check, instead of a separate language like OPA's Rego. | about 200 MB |
| Python API (FastAPI) | M7 to M8 | The workload the platform exists to run. It gives the pipeline something real to build, scan, deploy and monitor. | A common stack that hiring teams recognise. It replaced the blockchain RPC node in M4, which did not fit a 2 GB node. | about 100 MB |
| Postgres | M8 | The API's database. It makes the platform stateful, so I have to prove backups and tested restores (ADR-009). | The most common open-source relational database. | about 200 MB |
| Prometheus | M8 | Metrics and alerting for the API and the cluster. It feeds the SLOs in M10. | The standard metrics stack for Kubernetes. | about 400 MB |
| Embedded etcd, in place of SQLite | M8 | Cluster state survives a Spot interruption through scheduled snapshots to S3. | Built into K3s, and the path to more than one server later. It needs more memory than SQLite. | about 150 MB extra |
| **Total** | | | | **about 1.5 GiB** |

Loki and the OTel collector arrive in M10 and are not counted here. Even without them, a single t4g.small cannot hold this stack.

## Prices on 21 Oct 2026, ap-southeast-1a

| Instance | vCPU and RAM | Spot USD/hr | On-Demand USD/hr |
|---|---|---|---|
| t4g.small | 2 vCPU, 2 GiB | 0.0093 | 0.0212 |
| t4g.medium | 2 vCPU, 4 GiB | 0.0201 | 0.0424 |

Spot prices came from `aws ec2 describe-spot-price-history`. On-Demand prices came from the Price List API, which does not carry Spot prices. I use ap-southeast-1a because the node is pinned to that AZ, where the M8 Postgres volume will live.

## Options

| | 2x t4g.small (one server, one agent) | 1x t4g.medium (one server) |
|---|---|---|
| Spot cost per hour | 0.0186 | 0.0201 |
| Cost per 3-hour session | about $0.06 | about $0.06 |
| 24/7 Spot worst case per month | about $13.58, plus a second 20 GiB root volume at about $1.92 | about $14.67 |
| Memory for workloads | about 870 MiB on the server plus about 1.2 GiB on the agent, so about 2.1 GiB split across two nodes | about 2.8 GiB in one pool |
| Multi-node behaviour | Yes. Node join, scheduling across nodes, and draining a node | No |
| Spot interruption | Losing the agent leaves the control plane up | Losing the node takes the whole cluster down |
| Change needed | A second launch template, agent user data and a join token | One variable, `instance_type` |

The agent estimate uses the K3s agent figure of about 275 MB from the CNI posture memo, plus containerd and the OS. It is an estimate, not a measurement.

## Decision

I am moving the server to a t4g.medium for M6 to M8.

Memory decides this, not price. The two options cost within a cent per session of each other, and they cost the same On-Demand. The medium gives about 2.8 GiB in one pool, against about 2.1 GiB split across two smaller nodes. A pod can only use the free memory on the node it lands on, so the split matters for anything large like Prometheus or ArgoCD. The change is also one variable, so M6 starts on ArgoCD instead of agent plumbing.

A t4g.small agent joins in M9. The node rotation demo needs a second node to move workloads onto, so the agent arrives when it has a job to do.

## What I am accepting

- Until M9 the cluster is one node. A Spot interruption takes everything down until the next apply. Dev is rebuilt every session anyway, and once ArgoCD is in, workloads come back from git on their own.
- The workload figures are estimates. If ArgoCD alone lands well above 400 MB in M6, I will revisit this before Kyverno goes in.

## What changes elsewhere

- **M6.** Set `instance_type = "t4g.medium"` for the k3s-cluster module in dev. The Infracost delta and the Spot price at the time go in that PR. ADR-006 records this decision with a link to this note.
- **M8.** Moving to embedded etcd costs memory, and it comes out of the medium's headroom. I will measure it when it lands.
- **M9.** A t4g.small agent joins. The node security group already allows traffic between nodes in the same group, so no new firewall rules are needed.

## What would change this decision

- Measured workloads go past about 2.5 GiB on the medium. Then the M9 agent comes forward, or the server moves up a size.
- t4g.medium Spot capacity in ap-southeast-1a becomes unreliable. Then the mixed-instance ASG planned for M8 comes forward.
- I need the control plane to survive a node loss before M9. Then the two-node layout comes forward.
