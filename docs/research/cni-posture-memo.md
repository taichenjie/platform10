# CNI Posture Memo: K3s Embedded NetworkPolicy Controller vs Cilium

**Date:** 30 Sep 2026 (M4)
**Status:** Provisional decision. Input to ADR-006 (M6). To be confirmed by the M5 smoke-test memory baseline.

## Question

Which component enforces NetworkPolicy on the K3s cluster: the embedded controller that ships with K3s, or Cilium replacing flannel entirely?

## Context

The cluster runs on t4g.small Spot instances (2 vCPU, 2 GiB RAM, arm64). Flannel, the K3s default CNI, handles pod networking but does not enforce NetworkPolicy. Without an enforcing component, policies are accepted by the API server and do nothing.

The policy set planned for M7 needs default-deny ingress and egress in workload namespaces, a DNS egress allow, a monitoring scrape allow, and an API to Postgres allow on port 5432. All of these are standard `networking.k8s.io/v1` NetworkPolicy features.

## Options

**A. Keep flannel and the K3s embedded network policy controller (default).** K3s implements it with the kube-router netpol library. It is enabled by default and disabled only by `--disable-network-policy`. It runs inside the k3s process and enforces policy through iptables rules and ipsets. There is no separate pod.

**B. Replace flannel with Cilium.** Install K3s with `--flannel-backend=none` and `--disable-network-policy`, then install Cilium (agent DaemonSet plus operator). Cilium enforces policy with eBPF and adds L7 policies, FQDN-based egress, and flow visibility through Hubble.

## Memory evidence

| Component | Measured memory | Conditions | Source |
|---|---|---|---|
| K3s server + workload, single node | 1596 MB (SQLite) / 1606 MB (etcd) | c6id.xlarge, K3s v1.26.5, includes Prometheus + Grafana + an nginx deployment, 95th percentile steady state | K3s resource profiling docs |
| K3s agent | 275 MB | Same test | K3s resource profiling docs |
| K3s server minimum requirement | 2 GB RAM, 2 cores | Official requirements | K3s requirements docs |
| Embedded netpol controller | No separate process | Runs inside k3s; iptables + ipsets | K3s networking docs |
| cilium-agent (process RSS) | 71 to 132 MB per node | 5 nodes, ~77 pods, no policies, Cilium 1.12.5 | cilium/cilium issue #28772 |
| cilium-agent (Kubernetes working set) | 330 to 504 MB per node | Same cluster | cilium/cilium issue #28772 |
| cilium-agent at scale | 438 MiB average, 573 MiB max | 1000 nodes, 50,000 pods | Cilium scalability report |
| cilium-operator | Not sourced | Measure if Option B is ever trialled | None |

The two Cilium numbers differ because the Kubernetes working set includes kernel memory the cgroup accounts for (for example TCP socket buffers and page cache), which process RSS does not. The working set is what the kubelet uses for eviction decisions, so it is the number that matters for node stability.

## Budget arithmetic on a t4g.small

- Total node memory: 2048 MiB. Usable after the OS and kernel is lower. Exact figure to be recorded in the M5 baseline.
- K3s's own measured server plus a monitoring stack is about 1596 MB. That leaves roughly 400 MB before ArgoCD, Kyverno, Loki, the OTel collector, Postgres or the API are added.
- Option A adds no separate process.
- Option B adds 71 to 132 MB by RSS, or 330 to 504 MB by working set, plus the operator. By the eviction-relevant number, that is 16 to 25 percent of the node before the operator.

Cilium does not fit alongside the planned stack on this node class. The embedded controller costs nothing measurable.

## Enforcement coverage

| Requirement | Option A | Option B |
|---|---|---|
| Default-deny ingress and egress | Yes | Yes |
| podSelector, namespaceSelector, ipBlock | Yes | Yes |
| Port and protocol rules | Yes | Yes |
| L7 rules (HTTP method or path) | No | Yes |
| FQDN-based egress (for example `*.amazonaws.com`) | No | Yes |
| Flow logs and visibility into dropped traffic | No | Yes (Hubble) |

Every M7 requirement is in the rows both options support.

## Operational cost

Option A has no extra components to upgrade or monitor. Its costs are that denied traffic is silent (a dropped packet just times out, so debugging means reading policies rather than logs), iptables rules grow with pods and policies (irrelevant at tens of pods), and iptables rules are not removed if the controller is later disabled, so they must be cleaned up by hand.

Option B adds a DaemonSet, an operator, a Helm release to pin and upgrade, a kernel eBPF dependency, and a second networking stack to reason about during incidents.

## Provisional decision

Option A: flannel with the K3s embedded network policy controller. It enforces everything the M7 policy set needs, costs no measurable memory on a node already at the K3s minimum, and adds no components.

The module must never set `--disable-network-policy`. Enforcement is proven, not assumed, by the M5 smoke test: default-deny in a test namespace, a pod-to-pod curl that must time out, then the policy removed and the same curl must succeed.

## Triggers that flip the decision

1. The node class grows to 4 GiB or more with measured headroom for Cilium's working set.
2. A requirement appears for L7 policy, FQDN-based egress, or flow visibility.
3. Policy or pod counts reach a scale where iptables rule growth becomes measurable.
4. The platform moves to EKS. Amazon VPC CNI (v1.14 and later) enforces standard NetworkPolicy natively once enabled, so the choice there becomes VPC CNI's policy agent vs Cilium, not the K3s controller.

## Open risk: the node memory budget, not the CNI

K3s documents 2 GB as the minimum for a server node, which is exactly a t4g.small. Its own measured server with a monitoring stack uses about 1.6 GB. The full planned stack (ArgoCD, Kyverno, Prometheus, Grafana, Loki, OTel collector, Postgres, API) is unlikely to fit on one t4g.small.

Mitigations to evaluate with real numbers:

- The M6 two-node topology (server plus agent). The K3s agent baseline is 275 MB, and workloads move to the agent.
- A t4g.medium (4 GiB) server node, priced at M5 against current ap-southeast-1 Spot rates.
- The small-footprint posture already planned for M10 (short retention, longer scrape intervals, single replicas).

The M5 smoke test records the idle single-node baseline. Every later "will it fit" decision starts from that number.

## Sources

- K3s resource profiling: https://docs.k3s.io/reference/resource-profiling
- K3s requirements: https://docs.k3s.io/installation/requirements
- K3s networking services (embedded network policy controller): https://docs.k3s.io/networking/networking-services
- Cilium scalability report: https://docs.cilium.io/en/stable/operations/performance/scalability/report/
- cilium/cilium issue #28772 (agent RSS vs working set): https://github.com/cilium/cilium/issues/28772
- Amazon VPC CNI network policy support: https://docs.aws.amazon.com/eks/latest/userguide/cni-network-policy.html
