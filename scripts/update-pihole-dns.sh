#!/bin/bash
# Updates Pi-hole custom DNS entries for Proxmox nodes
# Compatible with Pi-hole v6 (uses /etc/pihole/hosts/ directory)
# Run from Mac with WireGuard connected and homelab SSH key loaded
# Usage: ./scripts/update-pihole-dns.sh

set -euo pipefail

PIHOLE="root@192.168.50.20"
SSH="ssh -F /dev/null -o IdentitiesOnly=yes -o ConnectTimeout=10 -i ~/.ssh/id_ed25519_homelab"

echo "Updating Pi-hole DNS entries on $PIHOLE..."

$SSH $PIHOLE bash <<'EOF'
HOSTS_DIR=/etc/pihole/hosts

# autobots/decepticons use management VXLAN (reachable via WireGuard)
# maximals uses LAN IP (no management VXLAN configured yet)
cat > $HOSTS_DIR/proxmox-nodes.hosts << 'HOSTS'
10.0.0.10 autobots.local.bp31app.com
10.0.0.11 decepticons.local.bp31app.com
192.168.50.99 maximals.local.bp31app.com
HOSTS

echo "Written to $HOSTS_DIR/proxmox-nodes.hosts:"
cat $HOSTS_DIR/proxmox-nodes.hosts

systemctl reload pihole-FTL
sleep 1

echo ""
echo "Testing resolution:"
dig autobots.local.bp31app.com @127.0.0.1 +short
dig decepticons.local.bp31app.com @127.0.0.1 +short
dig maximals.local.bp31app.com @127.0.0.1 +short
echo "Done."
EOF
