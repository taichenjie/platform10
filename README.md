# Platform 10

A single continuously evolving cloud platform built to demonstrate production-grade
infrastructure thinking, not a collection of tutorials.

**Live cost: sub-$10/month** at ap-southeast-1 standard pay-as-you-go rates.
On AWS Paid tier. Every resource billed from day one.
The invoice is in `docs/invoices/`.

## What this is

A self-healing, policy-enforced, GitOps-driven platform running an Ethereum/Solana
RPC node as its primary workload. Built on AWS and Terraform. Kubernetes via K3s,
not EKS. The [architecture decisions](docs/adr/) explain why and what migrating
would require.

## Stack

| Layer | Technology |
|---|---|
| Cloud | AWS (ap-southeast-1) |
| IaC | Terraform, sole source of truth |
| Compute | EC2 t4g (Arm) on Spot where possible |
| Orchestration | K3s (self-managed Kubernetes) |
| GitOps | ArgoCD with self-heal enabled |
| Policy | Kyverno admission control |
| Observability | Prometheus + Grafana + OpenTelemetry |
| CI/CD | GitHub Actions (CI) + ArgoCD (CD) |
| Cost gating | Infracost on every infrastructure PR |
| Secrets | SOPS + age |

## Quarter build status

- [x] Q1: Lean multi-AZ secure cloud foundation
- [ ] Q2: Immutable IaC engine, Terraform + CI/CD pipeline
- [ ] Q3: Production-grade K3s + GitOps engine
- [ ] Q4: Observability + thin self-service golden path

## What exists today (Q1)

A private-first multi-AZ network on AWS, built entirely in Terraform:

- VPC `10.0.0.0/16` with public and private subnets across two AZs
- Self-managed NAT instance (`t4g.nano`) for private-subnet egress, replacing
  a ~$43/mo managed NAT Gateway (see [ADR-001](docs/adr/ADR-001-self-managed-nat-instance.md))
- SSM Session Manager for access. No SSH, no bastion, no public-facing servers
- IAM permission boundary capping every non-root principal
- VPC endpoints for S3 (gateway), SSM and ECR (interface), keeping internal AWS
  API traffic off the public internet (see [ADR-002](docs/adr/ADR-002-single-az-interface-endpoints.md))
- Remote Terraform state in S3 with native locking (see [ADR-003](docs/adr/ADR-003-s3-remote-state-backend.md))

Worst-case 24/7 cost projection: ~$52/mo, dominated by the interface endpoints.
Actual spend is kept far lower by an apply/destroy workflow: the network is stood
up for a work session and torn down after, not left running. See `docs/cost/`.

## Deploying the Q1 foundation

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

Apply takes about 3 minutes.

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

## Repo structure
infra/terraform/

bootstrap/              S3 remote state backend (applied once, never destroyed)

environments/dev/       The dev environment: calls modules, holds IAM + backend config

modules/vpc/            Reusable VPC module: network, NAT, endpoints

files/                NAT instance cloud-init script

docs/

adr/                    Architecture decision records

cost/                   Infracost projections

invoices/               Real monthly AWS invoices

articles/               Blog post source notes

scripts/                  Cost-check and operational scripts

## Cost discipline

Every infrastructure PR shows an Infracost delta before apply.
Real monthly invoices are committed to `docs/invoices/`.
Architecture decisions include explicit cost arithmetic.

## Architecture decisions

All design choices are documented in [`docs/adr/`](docs/adr/).
Each ADR records the decision, the rationale, the trade-offs accepted,
and the production path that would undo them.

## The workload

An Ethereum/Solana pruned/testnet RPC node running as a Kubernetes workload,
monitored via Prometheus with block-height alerting and a committed resync runbook.

The platform is workload-agnostic. The RPC node is a deliberate choice for a
work-sample-driven hiring market. The same platform runs any equivalent stateful
service (for example a Postgres-backed API) without infrastructure changes.
