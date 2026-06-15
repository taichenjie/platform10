# Platform 10

A single continuously evolving cloud platform built to demonstrate production-grade
infrastructure thinking — not a collection of tutorials.

**Live cost: sub-$10/month** at ap-southeast-1 standard pay-as-you-go rates.
On AWS Paid tier. Every resource billed from day one.
The invoice is in `docs/invoices/`.

## What this is

A self-healing, policy-enforced, GitOps-driven platform running an Ethereum/Solana
RPC node as its primary workload. Built on AWS and Terraform. Kubernetes via K3s,
not EKS — the [architecture decision](docs/adr/) explains why and what migrating
would require.

## Stack

| Layer | Technology |
|---|---|
| Cloud | AWS (ap-southeast-1) |
| IaC | Terraform — sole source of truth |
| Compute | EC2 t4g (Arm) on Spot where possible |
| Orchestration | K3s (self-managed Kubernetes) |
| GitOps | ArgoCD with self-heal enabled |
| Policy | Kyverno admission control |
| Observability | Prometheus + Grafana + OpenTelemetry |
| CI/CD | GitHub Actions (CI) + ArgoCD (CD) |
| Cost gating | Infracost on every infrastructure PR |
| Secrets | SOPS + age |

## Quarter build status

- [x] Q1: Lean multi-AZ secure cloud foundation *(in progress)*
- [ ] Q2: Immutable IaC engine — Terraform + CI/CD pipeline
- [ ] Q3: Production-grade K3s + GitOps engine
- [ ] Q4: Observability + thin self-service golden path

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

The platform is workload-agnostic — the RPC node is a deliberate choice for a
work-sample-driven hiring market. The same platform runs any equivalent stateful
service (e.g. a Postgres-backed API) without infrastructure changes.
