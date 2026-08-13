#!/bin/bash
# NAT instance bootstrap for Amazon Linux 2023.
# Runs once on first boot via cloud-init.
#
# What this does, in order:
#   1. Update packages.
#   2. Install iptables-services so NAT rules persist across reboots.
#   3. Enable IPv4 forwarding in the kernel (required for any NAT).
#   4. Add a MASQUERADE rule so traffic from the VPC gets rewritten to
#      look like it came from this instance.
#   5. Save the rules and enable the service on boot.

# -e : exits immediately when any command fails
# -u : undefined variables return error
# -o pipefail : fail pipeline if any command fails
set -euo pipefail

# Log everything to /var/log/user-data.log so we can debug failures.
exec > >(tee /var/log/user-data.log) 2>&1

echo "NAT setup started at $(date)"

# 1. Update packages.
dnf update -y

# 2. iptables-services adds save/restore at boot. AL2023 ships nftables by
# default; the iptables command works as a wrapper, which is fine for us.
dnf install -y iptables-services

# 3. Detect the primary network interface. Hardcoding ens5 is fragile across
# instance families, so we read it from the default route.
PRIMARY_IFACE=$(ip -o -4 route show to default | awk '{print $5}')
echo "Primary interface: $PRIMARY_IFACE"

# 4. Enable IPv4 forwarding. Without this the kernel drops forwarded packets
# and nothing works. The drop-in file makes it survive reboot.
cat > /etc/sysctl.d/99-nat.conf <<SYSCTL
net.ipv4.ip_forward = 1
SYSCTL
sysctl --system

# 5. MASQUERADE rule: rewrite the source IP of outbound traffic from the VPC
# to this instance's IP. Scoped to the VPC CIDR so only legitimate VPC
# traffic gets NATed.
iptables -t nat -A POSTROUTING -o "$PRIMARY_IFACE" -s ${vpc_cidr} -j MASQUERADE

# 6. Save rules and make the service start on boot.
service iptables save
systemctl enable iptables

echo "NAT setup complete at $(date)"
