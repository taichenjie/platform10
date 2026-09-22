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
| Secrets | IAM permission boundary on every non-root principal |

## Planned (Q3-Q4)

| Layer | Technology |
|---|---|
| Orchestration | K3s (self-managed Kubernetes) |
| GitOps | ArgoCD |
| Policy | Kyverno admission control |
| Observability | Prometheus + Grafana + OpenTelemetry |
| CD | ArgoCD (CI stays in GitHub Actions) |
| Secrets | SOPS + age |
| Workload | Ethereum/Solana pruned RPC node |

## Quarter build status

- [x] Q1: Lean multi-AZ secure cloud foundation
- [x] Q2: Immutable IaC engine, Terraform + CI/CD pipeline
- [ ] Q3: Production-grade K3s + GitOps engine
- [ ] Q4: Observability + thin self-service golden path

## What exists today (v0.3.0, Q2 close)

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
  STS credentials. No static keys in GitHub Secrets. Trust policy pins three sub claim
  contexts (see [ADR-005](docs/adr/ADR-005-oidc-federation-for-github-actions-ci.md))
- Least-privilege permission policy scoped to the current 36-resource stack, with
  deliberate expansion tracked per month
- Three automated quality gates on every PR: code standards (fmt + tflint),
  security (Checkov hard-fail), cost visibility (Infracost)
- Terraform modules extracted and published to the Terraform Registry:
  [VPC](https://registry.terraform.io/modules/taichenjie/platform10-vpc/aws/latest),
  [IAM](https://registry.terraform.io/modules/taichenjie/platform10-iam/aws/latest),
  [Compute](https://registry.terraform.io/modules/taichenjie/platform10-compute/aws/latest)
- Module extraction via moved blocks with zero resource recreation
  (see [ADR-004](docs/adr/ADR-004-moved-block-refactor.md))

Worst-case 24/7 cost projection: ~$52/mo, dominated by the interface endpoints.
Actual spend is kept far lower by an apply/destroy workflow: the network is stood
up for a work session and torn down after, not left running. See `docs/cost/`.

## Deploying the Q1+Q2 foundation

### Prerequisites

- AWS account with an IAM user configured in the AWS CLI (this project uses `cj-admin`)
- Terraform `~> 1.15.5` (via `tfenv`)
- AWS CLI v2
- AWS Session Manager plugin (for the verify step)
- Region: `ap-southeast-1`

### One-time: create the state backend

The S3 bucket that holds Terraform state is created once by a separate bootstrap
config. It is intentionally isolated so that destroying the dev environment never
touches the state bucket.

```bash
cd infra/terraform/bootstrap
terraform init
terraform apply
```

### Deploy the network

```bash
cd infra/terraform/environments/dev
terraform init
terraform plan -var-file=dev.tfvars -out=tfplan.binary
terraform apply tfplan.binary
```

Apply takes about 3 minutes. The SSM agent on the NAT instance may take an
additional 1-2 minutes to register after apply completes.

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
control.

```bash
cd infra/terraform/environments/dev
terraform destroy -var-file=dev.tfvars
```

### Audit (confirm nothing is left billing)

```bash
aws ec2 describe-instances --filters "Name=tag:Project,Values=platform10" \
  "Name=instance-state-name,Values=running,stopped,pending,stopping" \
  --query "Reservations[].Instances[].InstanceId" --output text
aws ec2 describe-addresses --query "Addresses[].PublicIp" --output text
aws ec2 describe-vpc-endpoints --filters "Name=tag:Project,Values=platform10" \
  --query "VpcEndpoints[].VpcEndpointId" --output text
```

All three should return nothing.

## Repo Structure

```text
├── .github/workflows/
│   ├── terraform-plan.yml    # Plan on PR and push to main (fmt, tflint, Checkov, Infracost, plan)
│   └── terraform-apply.yml   # Gated apply on workflow_dispatch with environment approval
├── docs/
│   ├── adr/                  # Architecture decision records (ADR-001 through ADR-005)
│   ├── cost/                 # Infracost projections
│   ├── evidence/             # CI verification artifacts (OIDC negative test)
│   └── invoices/             # Real monthly AWS invoices
├── infra/terraform/
│   ├── bootstrap/            # S3 remote state backend (applied once, never destroyed)
│   ├── environments/dev/     # The dev environment: calls modules, holds IAM + backend config
│   └── modules/
│       ├── compute/          # Reusable compute module: NAT instance, SG, EIP
│       ├── iam/              # Reusable IAM module: roles, policies, OIDC federation
│       └── vpc/              # Reusable VPC module: network, endpoints
└── scripts/                  # Cost-check and operational scripts
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
