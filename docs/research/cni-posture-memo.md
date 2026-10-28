# CNI posture: K3s embedded NetworkPolicy controller vs Cilium

**First written:** 30 Sep 2026 (M4). **Updated:** 28 Oct 2026 (M5), after the smoke test.
**Status:** Decided in M5. Flannel with the K3s embedded controller. ADR-006 records it formally in M6.

## The question

A NetworkPolicy is only an API object. Something on the node has to turn it into firewall rules, or the policy does nothing. Flannel, the default K3s CNI, connects pods but does not enforce policy. To use NetworkPolicy, I considered 2 options.

## The two options

- **Option A.** Keep Flannel and the NetworkPolicy controller built into K3s. This is the K3s default.
- **Option B.** Replace Flannel with Cilium.

## What each one can do

| Capability | A. Flannel + K3s controller | B. Cilium |
|---|---|---|
| Pod networking | Flannel (VXLAN) | Cilium |
| How policy is enforced | iptables rules and ipsets on the node, written by a controller inside the K3s process (the kube-router library) | eBPF programs in the kernel |
| Default-deny ingress and egress | Yes | Yes |
| podSelector, namespaceSelector, ipBlock | Yes | Yes |
| Port and protocol rules | Yes | Yes |
| L7 rules, such as HTTP method or path | No | Yes |
| FQDN egress, such as allow `*.amazonaws.com` | No | Yes |
| Seeing which traffic was denied | No logs. Blocked connections are rejected straight away | Yes, through Hubble flow logs |
| Performance at thousands of pods and policies | iptables rules grow with pods and policies | eBPF scales better |

## What each one costs

| Cost | A. Flannel + K3s controller | B. Cilium |
|---|---|---|
| Extra memory | None. It runs inside K3s | cilium-agent about 330 to 504 MB per node by working set (71 to 132 MB by process RSS). Plus the operator, which I have no sourced figure for |
| Extra components | None | An agent DaemonSet, an operator, and a Helm release to pin and upgrade |
| K3s install changes | None | `--flannel-backend=none` and `--disable-network-policy`, then install Cilium |
| Kernel dependency | None beyond iptables | eBPF support in the kernel |
| Debugging | Read the policies, since there are no logs | Hubble shows denied flows, but there is a second networking stack to understand |

Working set is the figure the kubelet uses to decide evictions, so it is the one that matters for node stability. Process RSS is lower because it leaves out kernel memory such as socket buffers.

## What my cluster needs

The M7 policy set needs default-deny ingress and egress in workload namespaces, an egress allow for DNS, an allow for the Prometheus scrape, and an allow from the API to Postgres on port 5432. All of these are standard NetworkPolicy features, which both options support. Nothing planned for M7 to M9 needs L7 rules, FQDN egress or flow logs.

## Proof that Option A enforces

On 21 Oct 2026 I ran a negative test on the live cluster (K3s v1.35.9+k3s1, t4g.small). Two pods in a test namespace, a client and an nginx server, behind a Service.

| Step | Result |
|---|---|
| curl from client to server, no policy | HTTP 200 |
| Apply a default-deny ingress policy, curl again | Refused in 1 ms, curl exit code 7 |
| Delete the policy, curl again | HTTP 200 |

The refusal while the policy existed, with success before and after, shows the policy caused the block. The controller rejects blocked traffic rather than dropping it, so curl failed at once instead of timing out. I will confirm the REJECT rule with `iptables-save` at the next live session.

## Memory on my node

Measured on the idle t4g.small on 21 Oct 2026. Usable RAM was 1840 MiB. About 870 to 900 MiB was free, with `k3s-server` using about 610 to 625 MiB. The embedded controller is part of that `k3s-server` figure, so Option A cost nothing extra. Cilium's agent alone would have taken more than a third of the free memory.

## Decision

Option A. The K3s embedded controller enforces every policy my cluster needs, I proved it with a negative test, and it costs no extra memory or components. Cilium's strengths are L7 rules, FQDN egress, flow logs and scale, and none of them match a need in this project yet. It would be overkill. The module must never set `--disable-network-policy`.

## Why the t4g.medium does not change this

From M6 the server moves to a t4g.medium with 4 GiB, which meets the size part of my first trigger below. I am not switching. The extra memory is there for planned workloads such as ArgoCD, Postgres and Prometheus, not for a CNI swap. The trigger also needs measured headroom, and I will not have that until those workloads run. There is still no need for Cilium's features. The topology choice is in `docs/research/k3s-topology-decision.md`.

## When I would switch

1. The node has 4 GiB or more **and** measured headroom for Cilium's agent and operator, **and** one of the needs below exists.
2. A need for L7 policy, FQDN egress or flow logs appears.
3. Pod or policy counts grow to where iptables rule growth is measurable.
4. The platform moves to EKS. There, Amazon VPC CNI (v1.14 and later) enforces NetworkPolicy natively once enabled, so the choice becomes VPC CNI vs Cilium.

## Calico

Calico is the other common choice. It would replace Flannel, or run as Canal, which keeps Flannel for networking and adds Calico for policy. Either way it adds its own DaemonSet and controllers, and I have no sourced memory figures for them on arm64. Its extra features, such as cluster-wide policies and an optional eBPF dataplane, do not match a need in this project either. I did not measure it. If I ever trial an alternative, I will measure Calico and Cilium side by side on the same node.

## Sources

- K3s networking services (embedded NetworkPolicy controller): https://docs.k3s.io/networking/networking-services
- K3s requirements: https://docs.k3s.io/installation/requirements
- K3s resource profiling: https://docs.k3s.io/reference/resource-profiling
- Cilium scalability report: https://docs.cilium.io/en/stable/operations/performance/scalability/report/
- cilium/cilium issue #28772 (agent RSS vs working set): https://github.com/cilium/cilium/issues/28772
- Amazon VPC CNI network policy support: https://docs.aws.amazon.com/eks/latest/userguide/cni-network-policy.html
