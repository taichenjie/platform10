#!/bin/bash
# NAT instance bootstrap for Amazon Linux 2023 on t4g.nano.
# Runs once on first boot via cloud-init.
#
# What this does, in order:
#   1. Adds a 1 GiB swapfile so dnf has enough memory.
#   2. Installs iptables-services so NAT rules persist across reboots.
#   3. Finds the primary network interface.
#   4. Turns on IPv4 forwarding.
#   5. Adds a MASQUERADE rule for traffic from the VPC.
#   6. Saves the rules and enables the service on boot.
#   7. Checks that forwarding and the rule are live, or fails loudly.
#
# There is no "dnf update" here. The AMI comes from the SSM "latest"
# parameter, so it is already patched. On 16 Oct 2026 a full update ran
# out of memory on this 512 MB instance and the kernel killed dnf. The
# NAT was left half built: SSM Online, but forwarding nothing.

# -e : exit immediately when any command fails
# -u : treat undefined variables as errors
# -o pipefail : fail a pipeline if any command in it fails
set -euo pipefail

# Send all output, errors included, to /var/log/user-data.log.
exec > >(tee /var/log/user-data.log) 2>&1

log() { echo "$(date -u +%FT%TZ) $*"; }

log "NAT setup started"

# 1. Swapfile. The instance has about 412 MB usable RAM. dnf reading the
# AL2023 repo metadata peaked near 180 MB and was OOM-killed 33 seconds
# after boot. 1 GiB of swap on the encrypted root volume gives it room.
# It is not added to /etc/fstab on purpose. It is only needed for this
# one boot step and goes away on reboot.
if ! swapon --show=NAME --noheadings | grep -qx /swapfile; then
  log "Step 1: creating 1 GiB swapfile"
  fallocate -l 1G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
fi

# 2. iptables-services adds save and restore at boot. AL2023 ships
# nftables by default. The iptables command works as a wrapper over it.
# Up to 3 tries in case the package mirror has a hiccup.
log "Step 2: installing iptables-services"
for attempt in 1 2 3; do
  if dnf install -y --setopt=install_weak_deps=False iptables-services; then
    break
  fi
  if [ "$attempt" -eq 3 ]; then
    log "ERROR: dnf install failed 3 times"
    exit 1
  fi
  log "dnf install failed on try $attempt, retrying in 10 seconds"
  sleep 10
done

# 3. Read the primary interface from the default route. On Graviton it is
# usually ens5, but hardcoding it breaks across instance families.
PRIMARY_IFACE=$(ip -o -4 route show to default | awk '{print $5}')
if [ -z "$PRIMARY_IFACE" ]; then
  log "ERROR: no default route found"
  exit 1
fi
log "Step 3: primary interface is $PRIMARY_IFACE"

# 4. Turn on IPv4 forwarding. Without it the kernel silently drops every
# packet it is asked to forward. The drop-in file keeps it after reboot.
log "Step 4: enabling IPv4 forwarding"
cat > /etc/sysctl.d/99-nat.conf <<SYSCTL
net.ipv4.ip_forward = 1
SYSCTL
sysctl --system

# 5. MASQUERADE rewrites the source IP of outbound VPC traffic to this
# instance's IP, so replies come back here. Scoped to the VPC CIDR so
# only VPC traffic is NATed. -C checks first so a rerun adds no duplicate.
log "Step 5: adding MASQUERADE rule"
if ! iptables -t nat -C POSTROUTING -o "$PRIMARY_IFACE" -s ${vpc_cidr} -j MASQUERADE 2>/dev/null; then
  iptables -t nat -A POSTROUTING -o "$PRIMARY_IFACE" -s ${vpc_cidr} -j MASQUERADE
fi

# 6. Save the live rules to /etc/sysconfig/iptables and load them on boot.
log "Step 6: saving rules and enabling iptables on boot"
service iptables save
systemctl enable iptables

# 7. Verify. Being SSM Online does not prove this box is forwarding.
# Fail the boot script unless both pieces are actually live.
log "Step 7: verifying"
if [ "$(sysctl -n net.ipv4.ip_forward)" != "1" ]; then
  log "ERROR: ip_forward is not 1"
  exit 1
fi
if ! iptables -t nat -C POSTROUTING -o "$PRIMARY_IFACE" -s ${vpc_cidr} -j MASQUERADE; then
  log "ERROR: MASQUERADE rule is missing"
  exit 1
fi

log "NAT setup complete"
