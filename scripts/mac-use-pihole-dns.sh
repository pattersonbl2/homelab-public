#!/bin/bash
# Sets this Mac's DNS to Pi-hole so *.local.bp31app.com names resolve
# Requires WireGuard to be connected (Pi-hole is at 192.168.50.20)
#
# Usage:
#   ./scripts/mac-use-pihole-dns.sh        # set Pi-hole as DNS
#   ./scripts/mac-use-pihole-dns.sh restore # revert to DHCP DNS

set -euo pipefail

PIHOLE="192.168.50.20"
FALLBACK="1.1.1.1"

# Find the active network service (Wi-Fi or Ethernet)
INTERFACE=$(networksetup -listallnetworkservices | grep -v "^\*" | grep -E "Wi-Fi|Ethernet|USB" | head -1)

if [[ -z "$INTERFACE" ]]; then
  echo "ERROR: Could not detect active network interface."
  exit 1
fi

if [[ "${1:-}" == "restore" ]]; then
  echo "Restoring DNS to DHCP on '$INTERFACE'..."
  networksetup -setdnsservers "$INTERFACE" "Empty"
  networksetup -setsearchdomains "$INTERFACE" "Empty"
  echo "Done. DNS is now DHCP-assigned."
else
  echo "Setting DNS to Pi-hole ($PIHOLE) on '$INTERFACE'..."
  networksetup -setdnsservers "$INTERFACE" "$PIHOLE" "$FALLBACK"
  echo "Done. Testing resolution..."
  if dig +short +timeout=3 autobots.local.bp31app.com @"$PIHOLE" | grep -q '.'; then
    echo "✓ autobots.local.bp31app.com resolves correctly."
  else
    echo "⚠ Could not resolve autobots.local.bp31app.com — is WireGuard connected?"
  fi
fi
