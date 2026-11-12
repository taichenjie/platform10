# Platform 10

A single continuously evolving cloud platform built to demonstrate production-grade
infrastructure thinking, not a collection of tutorials.

**Live cost: sub-$10/month** at ap-southeast-1 standard pay-as-you-go rates.
On AWS paid tier. Every resource billed from day one.
The invoice is in `docs/invoices/`.

## What this is

A cloud platform on AWS, built entirely in Terraform, designed to run a stateful
workload on self-managed Kubernetes. The infrastructure is version-controlled,
CI-enforced, and documented through architecture decision records that explain
every trade-off.

The platform is being built in public over 12 months. The
[architecture decisions](docs/adr/) explain what exists, why, and what migrating
would require.

## Stack (what exists today)

| Layer | Technology |
|---|---|
| Cloud | AWS (ap-southeast-1) |
| IaC | Terraform, sole source of truth |
| Compute | EC2 t4g (Arm) |
| CI | GitHub Actions (plan on PR, gated apply on dispatch) |
| CI auth | OIDC federation, short-lived STS credentials (no static keys) |
| Code quality | tflint, Checkov (hard-fail), Infracost (cost-change visibility) |
| State | S3 backend with native locking |
| Access control | IAM permission boundary on every non-root principal |

## Planned (Q3-Q4)

| Layer | Technology |
|---|---|
| Orchestration | K3s (self-managed Kubernetes) |
| GitOps | ArgoCD |
| Policy | Kyverno admission control |
| Observability | Prometheus + Grafana + OpenTelemetry |
| CD | ArgoCD (CI stays in GitHub Actions) |
| Secrets | SOPS + age |
| Workload | Python API (FastAPI) + Postgres, operated as a StatefulSet with tested backups |

## Quarter build status

- [x] Q1: Lean multi-AZ secure cloud foundation
- [x] Q2: Immutable IaC engine, Terraform + CI/CD pipeline
- [ ] Q3: Production-grade K3s + GitOps engine
- [ ] Q4: Observability + thin self-service golden path

## What exists today (v0.3.0 at Q2 close, Q3 in progress)

### Q1 foundation

A private-first multi-AZ network on AWS, built entirely in Terraform.

- VPC `10.0.0.0/16` with public and private subnets across two AZs
- Self-managed NAT instance (`t4g.nano`) for private-subnet egress, replacing
  a ~$43/mo managed NAT Gateway (see [ADR-001](docs/adr/ADR-001-self-managed-nat-instance.md))
- SSM Session Manager for access. No SSH, no bastion, no public-facing servers
- IAM permission boundary capping every non-root principal
- VPC endpoints for S3 (gateway), SSM and ECR (interface), keeping internal AWS
  API traffic off the public internet (see [ADR-002](docs/adr/ADR-002-single-az-interface-endpoints.md))
- Remote Terraform state in S3 with native locking (see [ADR-003](docs/adr/ADR-003-s3-remote-state-backend.md))

### Q2 pipeline and security hardening

- OIDC federation for CI authentication. GitHub Actions authenticates via short-lived
  STS credentials. No static keys in GitHub Secrets. PR plans run as a read-only plan
  role. Only the approval-gated apply job can assume the write role, and it applies the
  saved plan the reviewer read (see [ADR-005](docs/adr/ADR-005-oidc-federation-for-github-actions-ci.md))
- Third-party actions pinned to full commit SHAs
- Least-privilege permission policy, expanded one resource type at a time as the
  stack grows
- Three automated quality gates on every PR: code standards (fmt + tflint),
  security (Checkov hard-fail), cost visibility (Infracost)
- Terraform modules extracted and published to the Terraform Registry:
  [VPC](https://registry.terraform.io/modules/taichenjie/platform10-vpc/aws/latest),
  [IAM](https://registry.terraform.io/modules/taichenjie/platform10-iam/aws/latest),
  [Compute](https://registry.terraform.io/modules/taichenjie/platform10-compute/aws/latest)
- Module extraction via moved blocks with zero resource recreation
  (see [ADR-004](docs/adr/ADR-004-moved-block-refactor.md))

### Q3 in progress: K3s cluster (M5)

- A `k3s-cluster` module: one K3s server on a Spot Graviton instance in a private
  subnet, reached only through SSM. IMDSv2 with hop limit 1, an encrypted gp3 root
  volume, and a security group that allows only node-to-node traffic and HTTPS out
  (see the [module README](infra/terraform/modules/k3s-cluster/README.md))
- K3s pinned one minor behind stable on purpose, to stage a real upgrade later
- NetworkPolicy enforcement proven by a negative test at cluster creation: allowed,
  then rejected under a default-deny policy, then allowed again
- An EventBridge rule that records Spot interruption warnings for the node
- Session scripts that rebuild the stack and wait until K3s is Ready, then destroy
  it and audit for leftovers
- Cluster size decided from a measured idle baseline: a t4g.medium server from M6
  (see [docs/research/](docs/research/))

Worst-case 24/7 cost projection: about $70/mo with the K3s node, dominated by the
interface endpoints.
Actual spend is kept far lower by an apply/destroy workflow: the network is stood
up for a work session and torn down after, not left running. See `docs/cost/`.

## Deploying

### Prerequisites

- AWS account with an IAM user configured in the AWS CLI (this project uses `cj-admin`)
- Terraform `~> 1.15.5` (via `tfenv`)
- AWS CLI v2
- AWS Session Manager plugin (for the verify step)
- Region: `ap-southeast-1`

### One-time: bootstrap (state backend and IAM)

Bootstrap creates the S3 bucket that holds Terraform state, and all IAM: the
permission boundary, the GitHub OIDC provider, the two CI roles (plan and apply), and
the EC2 SSM role and instance profile. It is intentionally isolated so that
destroying the dev environment never touches the state bucket or the identities
CI and the instances depend on.

Bootstrap is applied locally as `cj-admin`, never by CI (the CI roles' boundary
denies IAM writes), and it is never destroyed. Its own state lives in the same
bucket at `bootstrap/terraform.tfstate`. See ADR-012.

In an account that is already bootstrapped, plan before every change. CI does
not plan bootstrap, so nothing else catches drift.

```bash
cd infra/terraform/bootstrap
terraform init
terraform plan
```

Deploying into a new AWS account needs extra backend steps; see ADR-012.

### Deploy dev

Requires bootstrap. Dev reads the SSM instance profile with a data source, so
the plan fails at that lookup if bootstrap has not been applied. CI can also run
this apply through the manual `terraform-apply.yml` workflow.

The normal path is the session script. It runs the apply below, then waits until
the node is Online in SSM and K3s reports Ready:

```bash
./scripts/dev-apply.sh
```

To run the Terraform steps by hand:

```bash
cd infra/terraform/environments/dev
terraform init
terraform plan -var-file=dev.tfvars -out=tfplan.binary
terraform apply tfplan.binary
```

Apply creates 38 resources. On its first run the script took 2m57s from start to
K3s Ready.

### Verify

Find the NAT instance and open an SSM session:

```bash
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=platform10-dev-nat" \
  --query "Reservations[].Instances[].InstanceId" --output text

aws ssm start-session --target <instance-id>
```

Inside the instance, confirm the NAT is working:

```bash
sysctl net.ipv4.ip_forward                 # expect: net.ipv4.ip_forward = 1
sudo iptables -t nat -L POSTROUTING -v -n  # expect: a MASQUERADE rule for 10.0.0.0/16
curl -s ifconfig.me                        # expect: the NAT's Elastic IP
exit
```

### Destroy

The network is meant to be torn down after each work session. This is the cost
control. Destroy dev only. Never destroy bootstrap: the bucket has
`prevent_destroy`, and the IAM living in bootstrap is what CI needs to run.

```bash
./scripts/dev-destroy.sh
```

It runs `terraform destroy -var-file=dev.tfvars`, checks the state is empty, then
runs the audit below.

### Audit (confirm nothing is left billing)

```bash
./scripts/orphan-audit.sh
```

It counts 10 resource types that either cost money or would clash with the next
apply, and exits with an error if any are left.

## Repo Structure

```text
├── .github/workflows/
│   ├── terraform-plan.yml    # Plan on PRs to main (fmt, tflint, Checkov, Infracost, plan)
│   └── terraform-apply.yml   # Plan job, then gated apply of the saved plan (dispatch)
├── docs/
│   ├── adr/                  # Architecture decision records (ADR-001 to ADR-005, ADR-012)
│   ├── articles/             # Raw notes and capture plans for blog articles
│   ├── cost/                 # Infracost projections
│   ├── evidence/             # CI verification artifacts (OIDC negative test)
│   ├── research/             # Design research memos (ADR inputs)
│   └── invoices/             # Real monthly AWS invoices
├── infra/terraform/
│   ├── bootstrap/            # S3 state backend and all IAM (applied once locally, never destroyed)
│   ├── environments/dev/     # The dev environment: calls modules, reads the SSM profile from bootstrap
│   └── modules/
│       ├── compute/          # Reusable compute module: NAT instance, SG, EIP
│       ├── iam/              # Reusable IAM module: roles, policies, OIDC federation
│       ├── k3s-cluster/      # K3s server node: launch template, SG, Spot interruption rule
│       └── vpc/              # Reusable VPC module: network, endpoints
└── scripts/                  # Session apply/destroy, orphan audit, cost check
```

## Cost discipline

Every infrastructure PR shows an Infracost delta before merge.
Real monthly invoices are committed to `docs/invoices/`.
Architecture decisions include explicit cost arithmetic.

## Architecture decisions

All design choices are documented in [`docs/adr/`](docs/adr/).
Each ADR records the decision, the rationale, the trade-offs accepted,
and the production path that would undo them.

| ADR | Decision |
|---|---|
| [001](docs/adr/ADR-001-self-managed-nat-instance.md) | Self-managed NAT instance over managed NAT Gateway |
| [002](docs/adr/ADR-002-single-az-interface-endpoints.md) | Single-AZ interface endpoints |
| [003](docs/adr/ADR-003-s3-remote-state-backend.md) | S3 remote state backend with native locking |
| [004](docs/adr/ADR-004-moved-block-refactor.md) | Moved-block module extraction |
| [005](docs/adr/ADR-005-oidc-federation-for-github-actions-ci.md) | OIDC federation for GitHub Actions CI |

