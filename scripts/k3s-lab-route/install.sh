#!/bin/sh
# Install (or update) the K3s lab-route maintainer on this Mac.
#   sudo ./install.sh
set -e

SRC_DIR=$(cd "$(dirname "$0")" && pwd)
SCRIPT_DST=/usr/local/libexec/k3s-lab-route.sh
PLIST_DST=/Library/LaunchDaemons/com.bp31.k3s-lab-route.plist
SUDOERS_DST=/etc/sudoers.d/k3s-lab-route

[ "$(id -u)" -eq 0 ] || { echo "must run as root: sudo $0" >&2; exit 1; }

install -d -m 755 /usr/local/libexec
install -m 755 -o root -g wheel "$SRC_DIR/k3s-lab-route.sh" "$SCRIPT_DST"
install -m 644 -o root -g wheel "$SRC_DIR/com.bp31.k3s-lab-route.plist" "$PLIST_DST"

# On-demand runs without a password prompt. delete+add are both required:
# re-laying a present-but-dead route needs the delete.
cat > "$SUDOERS_DST" <<'SUDOERS'
bp31 ALL=(root) NOPASSWD: /usr/local/libexec/k3s-lab-route.sh
bp31 ALL=(root) NOPASSWD: /sbin/route add -net 10.10.10.0/24 192.168.50.18
bp31 ALL=(root) NOPASSWD: /sbin/route -n add -net 10.10.10.0/24 192.168.50.18
bp31 ALL=(root) NOPASSWD: /sbin/route delete -net 10.10.10.0/24 192.168.50.18
bp31 ALL=(root) NOPASSWD: /sbin/route -n delete -net 10.10.10.0/24 192.168.50.18
SUDOERS
chmod 440 "$SUDOERS_DST"
visudo -cf "$SUDOERS_DST" >/dev/null || { echo "sudoers validation failed" >&2; rm -f "$SUDOERS_DST"; exit 1; }

launchctl bootout system "$PLIST_DST" 2>/dev/null || true
launchctl bootstrap system "$PLIST_DST"
echo "installed; running once now:"
"$SCRIPT_DST"
echo "done"
