# IMDS Hop Limit Test

**Date:** 2026-11-14
**Cluster:** K3s v1.35.9+k3s1, single server, t4g.small, instance i-04a4765c59835b1c6
**Node setting:** IMDSv2 required, `http_put_response_hop_limit = 1`

## What I tested

The README says the hop limit keeps pods on the pod network away from the node's
IAM role, and that pods with hostNetwork bypass it. I tested both halves. Each pod
requests an IMDSv2 token and nothing more. A token is the first step to the
node's credentials, so a token issued is enough proof. I did not call the
credentials endpoint, and the response body was discarded, so no token was
printed.

## Test pods

Both pods ran in a throwaway `imds-test` namespace. They are identical except for
`hostNetwork`.

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: imds-podnet          # second pod: imds-hostnet
  namespace: imds-test
spec:
  # hostNetwork: true        # set on imds-hostnet only
  restartPolicy: Never
  containers:
    - name: curl
      image: curlimages/curl:8.23.0
      command:
        - sh
        - -c
        - >
          curl -s -o /dev/null --max-time 5
          -w 'http_code=%{http_code} time_total=%{time_total}s\n'
          -X PUT http://169.254.169.254/latest/api/token
          -H 'X-aws-ec2-metadata-token-ttl-seconds: 60';
          echo "curl exit=$?"
      resources:
        requests: { cpu: 10m, memory: 16Mi }
        limits: { cpu: 100m, memory: 64Mi }
```

Image digest pulled: `docker.io/curlimages/curl@sha256:3fb7e13e5d179a845c97d78204f3f1064d1907037f26a3ebf91710571151fd93`

Commands, run on the node through SSM.

```bash
alias k='sudo /usr/local/bin/k3s kubectl'
k -n imds-test wait --for=jsonpath='{.status.phase}'=Succeeded pod/imds-podnet --timeout=60s
k -n imds-test logs imds-podnet
k -n imds-test wait --for=jsonpath='{.status.phase}'=Succeeded pod/imds-hostnet --timeout=60s
k -n imds-test logs imds-hostnet
```

## Results

| Pod | Network | Output | Meaning |
|---|---|---|---|
| `imds-podnet` | Pod network (Flannel) | `http_code=000 time_total=5.001962s`, `curl exit=28` | No reply within 5s. The token response cannot make the extra hop into the pod |
| `imds-hostnet` | `hostNetwork: true` | `http_code=200 time_total=0.000789s`, `curl exit=0` | Token issued. The pod shares the node's network, so there is no extra hop |

The failure is a timeout (exit 28), not a refusal. IMDS receives the request, but
the reply is dropped when its hop limit runs out on the way back into the pod.

The cluster accepted the hostNetwork pod without any warning. Nothing in the
cluster prevents such a pod until the M7 admission policies land. From M7, Pod
Security Admission (Baseline) rejects hostNetwork and privileged pods in app
namespaces.

## Clean-up

Both pods were removed with `k delete namespace imds-test` before the stack was
destroyed. Orphan audit passed, EBS volumes 0.
