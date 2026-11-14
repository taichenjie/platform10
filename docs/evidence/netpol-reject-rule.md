# NetworkPolicy REJECT Rule

**Date:** 2026-11-14
**Cluster:** K3s v1.35.9+k3s1, single server, t4g.small, instance i-04a4765c59835b1c6
**Enforcer:** K3s embedded NetworkPolicy controller (kube-router library), Flannel

## What I tested

In M5 (21 Oct 2026) a denied connection failed at once with curl exit 7, not after
a timeout. I wrote that the embedded controller rejects denied traffic rather than
dropping it, but I had not seen the rule. This test finds the rule on the node.

## Setup

A throwaway `netpol-test` namespace with an nginx server pod behind a Service, and
a curl client pod. Both pods had requests and limits.

| Pod | Image digest pulled |
|---|---|
| `server` (`nginx:1.29-alpine`) | `docker.io/library/nginx@sha256:5616878291a2eed594aee8db4dade5878cf7edcb475e59193904b198d9b830de` |
| `client` (`curlimages/curl:8.23.0`) | `docker.io/curlimages/curl@sha256:3fb7e13e5d179a845c97d78204f3f1064d1907037f26a3ebf91710571151fd93` |

The policy denies all ingress to every pod in the namespace.

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: netpol-test
spec:
  podSelector: {}
  policyTypes:
    - Ingress
```

Amazon Linux 2023 has no `iptables-save` on the PATH. K3s ships its own copy, so I
used that one.

```bash
IPT=$(sudo find /var/lib/rancher/k3s/data -name 'iptables-save' -type f -o -name 'iptables-save' -type l | head -1)
# /var/lib/rancher/k3s/data/<hash>/bin/aux/iptables-save
sudo "$IPT" | grep -n 'REJECT'
```

## Results

| Step | Path | Result |
|---|---|---|
| No policy | client to Service | HTTP 200 |
| Policy applied | client to Service | curl exit 7 |
| Policy applied | client to server pod IP (10.42.0.9), no Service | curl exit 7 in 0.000259s |
| Policy deleted | client to server pod IP | HTTP 200 |
| Policy deleted | client to Service | HTTP 200 |

The rule that rejected the traffic, from the server pod's firewall chain.

```text
-A KUBE-POD-FW-AQSDX7RZPRJXZEBC -m comment --comment "rule to REJECT traffic destined for POD name:server namespace: netpol-test" -m mark ! --mark 0x10000/0x10000 -j REJECT --reject-with icmp-port-unreachable
```

The controller builds a `KUBE-POD-FW-*` chain for every pod. Traffic that a policy
allows gets the `0x10000` mark earlier in the chain. Anything without the mark
reaches this REJECT, which answers with an ICMP port-unreachable. That is why
curl fails in under a millisecond with exit 7 ("couldn't connect") instead of
waiting for a timeout (exit 28). All 112 `KUBE-POD-FW` lines were in the nft
backend (`iptables-nft-save`); the legacy backend held none.

## Why I tested the pod IP directly

The same `iptables-save` output also held a kube-proxy rule that rejects with the
same ICMP message.

```text
-A KUBE-SERVICES -d 10.43.17.234/32 -p tcp -m comment --comment "netpol-test/server has no endpoints" -m tcp --dport 80 -j REJECT --reject-with icmp-port-unreachable
```

With that rule present, exit 7 through the Service could have come from either
rule. Curling the pod IP skips the Service and kube-proxy, so only the
NetworkPolicy chain sits on that path. Exit 7 there, and 200 once the policy was
gone, shows the policy caused the rejection.

Open question. The "no endpoints" rule stayed listed while the Service had a ready
endpoint and answered 200, so it was not in the traffic path. It sits in the
filter table, which sees packets after the Service IP has been rewritten to the
pod IP, so a match on the Service IP never fires once an endpoint exists. I have
not confirmed why kube-proxy left it in place. Nothing above depends on it.

## Clean-up

The policy was deleted during the test and the namespace with
`k delete namespace netpol-test` before the stack was destroyed. Orphan audit
passed, EBS volumes 0.
