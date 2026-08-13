# Compute Module Extraction: Moved Block Evidence

**Date:** August 2026
**Branch:** feat/extract-compute-module
**PR:** #3
**Test method:** Applied all resources from main (compute resources inside module.vpc), switched to extraction branch, planned against live state.

## Moved block results

```
# module.vpc.aws_eip.nat has moved to module.compute.aws_eip.nat
  resource "aws_eip" "nat" {
      id                       = "eipalloc-xxxxxxxxxxxxxxxxx"
      # (11 unchanged attributes hidden)
  }

# module.vpc.aws_eip_association.nat has moved to module.compute.aws_eip_association.nat
  resource "aws_eip_association" "nat" {
      id                   = "eipassoc-xxxxxxxxxxxxxxxxx"
      # (5 unchanged attributes hidden)
  }

# module.vpc.aws_instance.nat has moved to module.compute.aws_instance.nat
  resource "aws_instance" "nat" {
      id                                   = "i-xxxxxxxxxxxxxxxxx"
      ami                                  = "ami-xxxxxxxxxxxxxxxxx"
      instance_type                        = "t3.micro"
      # (41 unchanged attributes hidden)
  }

# module.vpc.aws_route.private_nat has moved to module.compute.aws_route.private_nat
  resource "aws_route" "private_nat" {
      id                      = "r-rtb-xxxxxxxxxxxxxxxxx"
      # (6 unchanged attributes hidden)
  }

# module.vpc.aws_security_group.nat has moved to module.compute.aws_security_group.nat
  resource "aws_security_group" "nat" {
      id                     = "sg-xxxxxxxxxxxxxxxxx"
      name                   = "platform10-dev-nat-sg"
      # (9 unchanged attributes hidden)
  }

# module.vpc.aws_security_group_rule.nat_egress has moved to module.compute.aws_security_group_rule.nat_egress
  resource "aws_security_group_rule" "nat_egress" {
      id                = "sgrule-xxxxxxxxxxxxxxxxx"
      # (9 unchanged attributes hidden)
  }
```

## Plan summary

```
Plan: 0 to add, 0 to change, 0 to destroy.
```

## NAT drift fix included in this PR

The plan against live state originally showed a forced replacement on the NAT instance:

```
~ associate_public_ip_address = true -> false  # forces replacement
```

The AWS provider reads back true for this field after an EIP is attached, regardless of what the code declares. The subnet already has map_public_ip_on_launch = false, which prevents auto-assigned public IPs. Fix: remove associate_public_ip_address from the instance resource entirely. After the fix, the plan showed (41 unchanged attributes hidden) on the NAT instance, confirming zero drift.

This drift was latent since M1 and only surfaced because the moved-block test was the first plan run against live, EIP-associated infrastructure.

## What this proves

- Six compute resources changed Terraform address from module.vpc to module.compute.
- Every resource shows "has moved to" with unchanged attributes.
- No resource was destroyed, created, or modified in AWS.
- The NAT drift bug was caught and fixed as part of this extraction.
- State was updated in place. Zero downtime.
