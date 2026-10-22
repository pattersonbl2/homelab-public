#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# mgmt-isolation.sh — Isolate Proxmox management onto VXLAN overlay (10.0.0.0/24)
#
# Run from Mac. Executes in phases with verification between each.
# SSH to LAN IPs stays open as safety net throughout.
# =============================================================================

SSH_KEY="$HOME/.ssh/id_ed25519_homelab"
SSH_OPTS="-F /dev/null -o IdentitiesOnly=yes -o StrictHostKeyChecking=no -o ConnectTimeout=10 -i $SSH_KEY"
PVE_IP="192.168.50.176"
PVE2_IP="192.168.50.26"
VYOS_IP="192.168.50.18"
MGMT_PVE="10.0.0.10"
MGMT_PVE2="10.0.0.11"
MGMT_GW="10.0.0.1"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
fail()  { echo -e "${RED}[FAIL]${NC} $*"; }

confirm() {
    echo ""
    echo -e "${YELLOW}──────────────────────────────────────────${NC}"
    echo -e "${YELLOW}$1${NC}"
    echo -e "${YELLOW}──────────────────────────────────────────${NC}"
    read -rp "Continue? [y/N] " ans
    [[ "$ans" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 1; }
    echo ""
}

run_pve()  { ssh $SSH_OPTS "root@${PVE_IP}" "$@"; }
run_pve2() { ssh $SSH_OPTS "root@${PVE2_IP}" "$@"; }
run_vyos() { ssh $SSH_OPTS "vyos@${VYOS_IP}" "$@"; }

# =============================================================================
# PHASE 1: Add VXLAN + vmbr2 to both Proxmox nodes
# =============================================================================
phase1() {
    info "PHASE 1: Adding VXLAN overlay + vmbr2 to both nodes"
    info "This adds config to /etc/network/interfaces — no restart yet"

    # --- pve ---
    info "Checking if vmbr2 already exists on pve..."
    if run_pve "grep -q 'auto vmbr2' /etc/network/interfaces"; then
        warn "vmbr2 already in pve /etc/network/interfaces — skipping"
    else
        info "Adding VXLAN + vmbr2 to pve..."
        run_pve 'cat >> /etc/network/interfaces << '\''BLOCK'\''

# --- VXLAN for management overlay ---
auto vxlan20
iface vxlan20 inet manual
    pre-up ip link add vxlan20 type vxlan id 20 \
        local 192.168.50.176 \
        remote 192.168.50.26 \
        dstport 4789
    up ip link set vxlan20 up
    down ip link set vxlan20 down
    post-down ip link del vxlan20

# --- Management bridge (VXLAN-backed, no physical NIC) ---
auto vmbr2
iface vmbr2 inet static
    address 10.0.0.10/24
    up ip route add 10.10.11.0/24 via 10.0.0.1 dev vmbr2
    bridge-ports vxlan20
    bridge-stp off
    bridge-fd 0
BLOCK'
        ok "pve: vmbr2 config added"
    fi

    # --- pve2 ---
    info "Checking if vmbr2 already exists on pve2..."
    if run_pve2 "grep -q 'auto vmbr2' /etc/network/interfaces"; then
        warn "vmbr2 already in pve2 /etc/network/interfaces — skipping"
    else
        info "Adding VXLAN + vmbr2 to pve2..."
        run_pve2 'cat >> /etc/network/interfaces << '\''BLOCK'\''

# --- VXLAN for management overlay ---
auto vxlan20
iface vxlan20 inet manual
    pre-up ip link add vxlan20 type vxlan id 20 \
        local 192.168.50.26 \
        remote 192.168.50.176 \
        dstport 4789
    up ip link set vxlan20 up
    down ip link set vxlan20 down
    post-down ip link del vxlan20

# --- Management bridge (VXLAN-backed, no physical NIC) ---
auto vmbr2
iface vmbr2 inet static
    address 10.0.0.11/24
    up ip route add 10.10.11.0/24 via 10.0.0.1 dev vmbr2
    bridge-ports vxlan20
    bridge-stp off
    bridge-fd 0
BLOCK'
        ok "pve2: vmbr2 config added"
    fi

    echo ""
    info "Config written. Now applying with ifreload on both nodes..."

    confirm "About to run 'ifreload -a' on pve and pve2. This applies network changes live."

    info "Applying on pve..."
    run_pve "ifreload -a" 2>&1 || warn "ifreload had warnings on pve (may be OK)"
    ok "pve: ifreload complete"

    info "Applying on pve2..."
    run_pve2 "ifreload -a" 2>&1 || warn "ifreload had warnings on pve2 (may be OK)"
    ok "pve2: ifreload complete"

    # Brief wait for VXLAN to establish
    sleep 2

    ok "Phase 1 complete — VXLAN + vmbr2 added to both nodes"
}

# =============================================================================
# PHASE 2: Verify VXLAN connectivity
# =============================================================================
phase2() {
    info "PHASE 2: Verifying VXLAN connectivity"

    info "Checking vmbr2 exists on pve..."
    if run_pve "ip addr show vmbr2" &>/dev/null; then
        ok "pve: vmbr2 is up"
        run_pve "ip -4 addr show vmbr2 | grep inet"
    else
        fail "pve: vmbr2 not found — check /etc/network/interfaces and run 'ifreload -a'"
        return 1
    fi

    info "Checking vmbr2 exists on pve2..."
    if run_pve2 "ip addr show vmbr2" &>/dev/null; then
        ok "pve2: vmbr2 is up"
        run_pve2 "ip -4 addr show vmbr2 | grep inet"
    else
        fail "pve2: vmbr2 not found — check /etc/network/interfaces and run 'ifreload -a'"
        return 1
    fi

    info "Checking VXLAN tunnel (pve → pve2 on 10.0.0.11)..."
    if run_pve "ping -c 3 -W 2 ${MGMT_PVE2}" &>/dev/null; then
        ok "pve → pve2 VXLAN connectivity confirmed"
    else
        fail "pve cannot ping pve2 on management network"
        warn "Check: VXLAN multicast 239.1.1.20 may be blocked, or ifreload didn't apply"
        return 1
    fi

    info "Checking VXLAN tunnel (pve2 → pve on 10.0.0.10)..."
    if run_pve2 "ping -c 3 -W 2 ${MGMT_PVE}" &>/dev/null; then
        ok "pve2 → pve VXLAN connectivity confirmed"
    else
        fail "pve2 cannot ping pve on management network"
        return 1
    fi

    ok "Phase 2 complete — VXLAN overlay is working"
}

# =============================================================================
# PHASE 3: Add 3rd NIC to VyOS VM + configure eth2
# =============================================================================
phase3() {
    info "PHASE 3: Adding management NIC to VyOS and configuring eth2"

    # Check if VyOS VM 200 already has net2
    info "Checking if VyOS VM 200 already has net2..."
    if run_pve "qm config 200 | grep -q 'net2:'"; then
        warn "VyOS VM 200 already has net2 — skipping NIC add"
    else
        info "Adding net2 (vmbr2) to VyOS VM 200..."
        run_pve "qm set 200 -net2 virtio,bridge=vmbr2"
        ok "NIC added to VM 200"

        # VyOS needs a reboot or hotplug to see the new NIC
        # Try hotplug first via QMP, fall back to reboot advice
        warn "VyOS may need a reboot to detect eth2."
        confirm "Reboot VyOS VM 200? VMs on vmbr1 will briefly lose their gateway."
        info "Rebooting VyOS..."
        run_pve "qm reboot 200"
        info "Waiting 30s for VyOS to come back..."
        sleep 30

        # Verify VyOS is back
        local retries=0
        while ! run_vyos "echo ok" &>/dev/null; do
            retries=$((retries + 1))
            if [ $retries -gt 12 ]; then
                fail "VyOS not responding after 90s"
                return 1
            fi
            info "Waiting for VyOS... (${retries}/12)"
            sleep 5
        done
        ok "VyOS is back online"
    fi

    # Check if eth2 is already configured
    info "Checking if eth2 is already configured in VyOS..."
    if run_vyos "/opt/vyatta/bin/vyatta-op-cmd-wrapper show configuration commands" 2>/dev/null | grep -q "eth2 address"; then
        warn "VyOS eth2 already configured — skipping"
    else
        info "Configuring VyOS eth2 + management routing + firewall..."
        run_vyos '/opt/vyatta/sbin/vyatta-cfg-cmd-wrapper begin
/opt/vyatta/sbin/vyatta-cfg-cmd-wrapper set interfaces ethernet eth2 address "10.0.0.1/24"
/opt/vyatta/sbin/vyatta-cfg-cmd-wrapper set interfaces ethernet eth2 description "MGMT - vmbr2"

# NAT management network outbound
/opt/vyatta/sbin/vyatta-cfg-cmd-wrapper set nat source rule 110 outbound-interface name "eth0"
/opt/vyatta/sbin/vyatta-cfg-cmd-wrapper set nat source rule 110 source address "10.0.0.0/24"
/opt/vyatta/sbin/vyatta-cfg-cmd-wrapper set nat source rule 110 translation address "masquerade"

# DNS for management network
/opt/vyatta/sbin/vyatta-cfg-cmd-wrapper set service dns forwarding allow-from "10.0.0.0/24"
/opt/vyatta/sbin/vyatta-cfg-cmd-wrapper set service dns forwarding listen-address "10.0.0.1"

# Firewall: MGMT → WAN (allow essentials only)
/opt/vyatta/sbin/vyatta-cfg-cmd-wrapper set firewall ipv4 name MGMT-IN default-action "drop"
/opt/vyatta/sbin/vyatta-cfg-cmd-wrapper set firewall ipv4 name MGMT-IN rule 10 action "accept"
/opt/vyatta/sbin/vyatta-cfg-cmd-wrapper set firewall ipv4 name MGMT-IN rule 10 state "established"
/opt/vyatta/sbin/vyatta-cfg-cmd-wrapper set firewall ipv4 name MGMT-IN rule 20 action "accept"
/opt/vyatta/sbin/vyatta-cfg-cmd-wrapper set firewall ipv4 name MGMT-IN rule 20 state "related"
/opt/vyatta/sbin/vyatta-cfg-cmd-wrapper set firewall ipv4 name MGMT-IN rule 100 action "accept"
/opt/vyatta/sbin/vyatta-cfg-cmd-wrapper set firewall ipv4 name MGMT-IN rule 100 description "Allow DNS"
/opt/vyatta/sbin/vyatta-cfg-cmd-wrapper set firewall ipv4 name MGMT-IN rule 100 destination port "53"
/opt/vyatta/sbin/vyatta-cfg-cmd-wrapper set firewall ipv4 name MGMT-IN rule 100 protocol "tcp_udp"
/opt/vyatta/sbin/vyatta-cfg-cmd-wrapper set firewall ipv4 name MGMT-IN rule 110 action "accept"
/opt/vyatta/sbin/vyatta-cfg-cmd-wrapper set firewall ipv4 name MGMT-IN rule 110 description "Allow HTTP/HTTPS for apt"
/opt/vyatta/sbin/vyatta-cfg-cmd-wrapper set firewall ipv4 name MGMT-IN rule 110 destination port "80,443"
/opt/vyatta/sbin/vyatta-cfg-cmd-wrapper set firewall ipv4 name MGMT-IN rule 110 protocol "tcp"
/opt/vyatta/sbin/vyatta-cfg-cmd-wrapper set firewall ipv4 name MGMT-IN rule 120 action "accept"
/opt/vyatta/sbin/vyatta-cfg-cmd-wrapper set firewall ipv4 name MGMT-IN rule 120 description "Allow QDevice to VPS"
/opt/vyatta/sbin/vyatta-cfg-cmd-wrapper set firewall ipv4 name MGMT-IN rule 120 destination address "REDACTED_VPS_IP"
/opt/vyatta/sbin/vyatta-cfg-cmd-wrapper set firewall ipv4 name MGMT-IN rule 120 destination port "5403"
/opt/vyatta/sbin/vyatta-cfg-cmd-wrapper set firewall ipv4 name MGMT-IN rule 120 protocol "tcp"

# Firewall: WAN → MGMT (only WireGuard clients)
/opt/vyatta/sbin/vyatta-cfg-cmd-wrapper set firewall ipv4 name WAN-TO-MGMT default-action "drop"
/opt/vyatta/sbin/vyatta-cfg-cmd-wrapper set firewall ipv4 name WAN-TO-MGMT rule 10 action "accept"
/opt/vyatta/sbin/vyatta-cfg-cmd-wrapper set firewall ipv4 name WAN-TO-MGMT rule 10 state "established"
/opt/vyatta/sbin/vyatta-cfg-cmd-wrapper set firewall ipv4 name WAN-TO-MGMT rule 20 action "accept"
/opt/vyatta/sbin/vyatta-cfg-cmd-wrapper set firewall ipv4 name WAN-TO-MGMT rule 20 state "related"
/opt/vyatta/sbin/vyatta-cfg-cmd-wrapper set firewall ipv4 name WAN-TO-MGMT rule 100 action "accept"
/opt/vyatta/sbin/vyatta-cfg-cmd-wrapper set firewall ipv4 name WAN-TO-MGMT rule 100 description "Allow WireGuard clients to mgmt"
/opt/vyatta/sbin/vyatta-cfg-cmd-wrapper set firewall ipv4 name WAN-TO-MGMT rule 100 source address "10.10.11.0/24"
/opt/vyatta/sbin/vyatta-cfg-cmd-wrapper set firewall ipv4 name WAN-TO-MGMT rule 100 protocol "tcp"
/opt/vyatta/sbin/vyatta-cfg-cmd-wrapper set firewall ipv4 name WAN-TO-MGMT rule 100 destination port "8006,22"

# Apply firewall to eth2
/opt/vyatta/sbin/vyatta-cfg-cmd-wrapper set firewall interface eth2 in name "MGMT-IN"

/opt/vyatta/sbin/vyatta-cfg-cmd-wrapper commit
/opt/vyatta/sbin/vyatta-cfg-cmd-wrapper save
/opt/vyatta/sbin/vyatta-cfg-cmd-wrapper end'
        ok "VyOS eth2 configured with management routing + firewall"
    fi

    # Verify VyOS can reach both nodes on mgmt
    info "Verifying VyOS → pve on management..."
    if run_vyos "ping -c 2 -W 2 ${MGMT_PVE}" &>/dev/null; then
        ok "VyOS → pve (${MGMT_PVE}) OK"
    else
        fail "VyOS cannot reach pve on ${MGMT_PVE}"
    fi

    info "Verifying VyOS → pve2 on management..."
    if run_vyos "ping -c 2 -W 2 ${MGMT_PVE2}" &>/dev/null; then
        ok "VyOS → pve2 (${MGMT_PVE2}) OK"
    else
        fail "VyOS cannot reach pve2 on ${MGMT_PVE2}"
    fi

    ok "Phase 3 complete — VyOS management interface configured"
}

# =============================================================================
# PHASE 4: Update WireGuard client config
# =============================================================================
phase4() {
    info "PHASE 4: WireGuard client update"

    local wg_conf="/opt/homebrew/etc/wireguard/homelab.conf"

    if [ -f "$wg_conf" ]; then
        info "Current WireGuard config:"
        grep -i "allowedips" "$wg_conf" || true
        echo ""
        warn "You need to add 10.0.0.0/24 to AllowedIPs in your WireGuard config."
        warn "Edit: $wg_conf"
        echo ""
        echo "  AllowedIPs should include: 10.10.10.0/24, 10.10.11.0/24, 10.0.0.0/24"
        echo ""
        confirm "Have you updated the WireGuard config and reconnected? (do it now, then press y)"
    else
        warn "WireGuard config not found at $wg_conf"
        warn "Make sure 10.0.0.0/24 is in AllowedIPs on your VPN client."
        confirm "Ready to continue?"
    fi

    # Test management access via WireGuard
    info "Testing management access from this machine..."
    if ping -c 2 -W 2 "${MGMT_PVE}" &>/dev/null; then
        ok "Can reach pve at ${MGMT_PVE}"
    else
        fail "Cannot reach pve at ${MGMT_PVE} — is WireGuard up with 10.0.0.0/24 routed?"
        warn "Run: sudo wg-quick down homelab && sudo wg-quick up homelab"
        return 1
    fi

    if ping -c 2 -W 2 "${MGMT_PVE2}" &>/dev/null; then
        ok "Can reach pve2 at ${MGMT_PVE2}"
    else
        fail "Cannot reach pve2 at ${MGMT_PVE2}"
        return 1
    fi

    echo ""
    info "Try accessing the Proxmox UI now:"
    echo "  https://${MGMT_PVE}:8006"
    echo "  https://${MGMT_PVE2}:8006"
    confirm "Can you access both Proxmox UIs via management IPs?"

    ok "Phase 4 complete — management access via WireGuard confirmed"
}

# =============================================================================
# PHASE 5: Update /etc/hosts (makes Proxmox UI reference mgmt IPs)
# =============================================================================
phase5() {
    info "PHASE 5: Updating /etc/hosts on both nodes"
    warn "This changes how Proxmox references nodes in the UI and API calls."
    warn "Corosync is NOT affected (uses ring0_addr from corosync.conf)."
    confirm "Update /etc/hosts on pve and pve2?"

    # --- pve ---
    info "Backing up pve /etc/hosts..."
    run_pve "cp /etc/hosts /etc/hosts.bak.$(date +%Y%m%d)"

    info "Updating pve /etc/hosts..."
    run_pve 'cat > /etc/hosts << '\''EOF'\''
127.0.0.1 localhost.localdomain localhost
10.0.0.10 pve.bp31app.com pve
10.0.0.11 pve2.bp31app.com pve2
192.168.50.55 autentik.local.bp31app.com
# Corosync uses ring0_addr (192.168.50.x) from corosync.conf, not /etc/hosts

::1     ip6-localhost ip6-loopback
fe00::0 ip6-localnet
ff00::0 ip6-mcastprefix
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
ff02::3 ip6-allhosts
EOF'
    ok "pve: /etc/hosts updated"

    # --- pve2 ---
    info "Backing up pve2 /etc/hosts..."
    run_pve2 "cp /etc/hosts /etc/hosts.bak.$(date +%Y%m%d)"

    info "Updating pve2 /etc/hosts..."
    run_pve2 'cat > /etc/hosts << '\''EOF'\''
127.0.0.1 localhost.localdomain localhost
10.0.0.11 pve2.bp31app.com pve2
10.0.0.10 pve.bp31app.com pve
# Corosync uses ring0_addr (192.168.50.x) from corosync.conf, not /etc/hosts

::1     ip6-localhost ip6-loopback
fe00::0 ip6-localnet
ff00::0 ip6-mcastprefix
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
ff02::3 ip6-allhosts
EOF'
    ok "pve2: /etc/hosts updated"

    # Restart pveproxy so it picks up the new hostname resolution
    info "Restarting pveproxy on both nodes..."
    run_pve "systemctl restart pveproxy"
    run_pve2 "systemctl restart pveproxy"
    ok "pveproxy restarted"

    # Verify cluster still healthy
    info "Checking Corosync cluster health..."
    run_pve "pvecm status" 2>&1 | grep -E "Cluster|Node|Votequorum" || true
    echo ""

    info "Verify the Proxmox UI still works at:"
    echo "  https://${MGMT_PVE}:8006"
    echo "  https://${MGMT_PVE2}:8006"
    confirm "Proxmox UI works and shows correct node references?"

    ok "Phase 5 complete — /etc/hosts updated, Proxmox references management IPs"
}

# =============================================================================
# PHASE 6: Lock down port 8006 on LAN interface
# =============================================================================
phase6() {
    info "PHASE 6: Blocking Proxmox UI (8006) on LAN interface"
    warn "After this, port 8006 is ONLY reachable via management network (10.0.0.0/24)."
    warn "SSH on LAN IPs stays open as emergency access."
    confirm "Apply iptables lockdown on both nodes?"

    # --- pve ---
    info "Adding iptables rule on pve..."
    run_pve 'iptables -C INPUT -i vmbr0 -p tcp --dport 8006 -j DROP 2>/dev/null || \
        iptables -I INPUT -i vmbr0 -p tcp --dport 8006 -j DROP'
    ok "pve: port 8006 blocked on vmbr0"

    # --- pve2 ---
    info "Adding iptables rule on pve2..."
    run_pve2 'iptables -C INPUT -i vmbr0 -p tcp --dport 8006 -j DROP 2>/dev/null || \
        iptables -I INPUT -i vmbr0 -p tcp --dport 8006 -j DROP'
    ok "pve2: port 8006 blocked on vmbr0"

    # Make persistent across reboots
    info "Making iptables rules persistent..."

    run_pve 'mkdir -p /etc/network/if-up.d && cat > /etc/network/if-up.d/mgmt-firewall << '\''SCRIPT'\''
#!/bin/sh
# Block Proxmox UI on LAN — force access via management network (vmbr2)
if [ "$IFACE" = "vmbr2" ]; then
    iptables -C INPUT -i vmbr0 -p tcp --dport 8006 -j DROP 2>/dev/null || \
        iptables -I INPUT -i vmbr0 -p tcp --dport 8006 -j DROP
fi
SCRIPT
chmod +x /etc/network/if-up.d/mgmt-firewall'
    ok "pve: persistent iptables script created"

    run_pve2 'mkdir -p /etc/network/if-up.d && cat > /etc/network/if-up.d/mgmt-firewall << '\''SCRIPT'\''
#!/bin/sh
# Block Proxmox UI on LAN — force access via management network (vmbr2)
if [ "$IFACE" = "vmbr2" ]; then
    iptables -C INPUT -i vmbr0 -p tcp --dport 8006 -j DROP 2>/dev/null || \
        iptables -I INPUT -i vmbr0 -p tcp --dport 8006 -j DROP
fi
SCRIPT
chmod +x /etc/network/if-up.d/mgmt-firewall'
    ok "pve2: persistent iptables script created"

    # Verify
    echo ""
    info "Verification — try accessing the OLD LAN URLs (should FAIL):"
    echo "  https://192.168.50.176:8006  ← should timeout"
    echo "  https://192.168.50.26:8006   ← should timeout"
    echo ""
    info "These should still work:"
    echo "  https://${MGMT_PVE}:8006     ← management network"
    echo "  https://${MGMT_PVE2}:8006    ← management network"
    echo "  ssh root@192.168.50.176      ← emergency SSH (still open)"

    ok "Phase 6 complete — Proxmox UI locked to management network"
}

# =============================================================================
# ROLLBACK — undo everything if needed
# =============================================================================
rollback() {
    warn "ROLLBACK: Undoing management isolation"
    confirm "This will remove vmbr2, revert /etc/hosts, and remove iptables rules. Continue?"

    # Remove iptables
    info "Removing iptables rules..."
    run_pve "iptables -D INPUT -i vmbr0 -p tcp --dport 8006 -j DROP 2>/dev/null; rm -f /etc/network/if-up.d/mgmt-firewall" || true
    run_pve2 "iptables -D INPUT -i vmbr0 -p tcp --dport 8006 -j DROP 2>/dev/null; rm -f /etc/network/if-up.d/mgmt-firewall" || true

    # Restore /etc/hosts
    info "Restoring /etc/hosts from backup..."
    run_pve 'latest=$(ls -t /etc/hosts.bak.* 2>/dev/null | head -1); [ -n "$latest" ] && cp "$latest" /etc/hosts && echo "Restored from $latest"' || warn "No backup found on pve"
    run_pve2 'latest=$(ls -t /etc/hosts.bak.* 2>/dev/null | head -1); [ -n "$latest" ] && cp "$latest" /etc/hosts && echo "Restored from $latest"' || warn "No backup found on pve2"

    # Restart pveproxy
    run_pve "systemctl restart pveproxy" || true
    run_pve2 "systemctl restart pveproxy" || true

    # Remove VyOS eth2 NIC from VM
    info "Removing net2 from VyOS VM 200..."
    run_pve "qm set 200 -delete net2" || true

    # Remove vmbr2 + vxlan20 from interfaces
    info "Removing vmbr2 config from pve..."
    run_pve "sed -i '/^# --- VXLAN for management overlay ---/,\$d' /etc/network/interfaces && ifreload -a" || true
    info "Removing vmbr2 config from pve2..."
    run_pve2 "sed -i '/^# --- VXLAN for management overlay ---/,\$d' /etc/network/interfaces && ifreload -a" || true

    ok "Rollback complete. Reboot VyOS (qm reboot 200) to remove eth2 from its view."
    ok "Access Proxmox at https://192.168.50.176:8006 and https://192.168.50.26:8006"
}

# =============================================================================
# MAIN
# =============================================================================
usage() {
    echo "Usage: $0 [phase1|phase2|phase3|phase4|phase5|phase6|all|rollback]"
    echo ""
    echo "Phases:"
    echo "  phase1   Add VXLAN + vmbr2 to both Proxmox nodes"
    echo "  phase2   Verify VXLAN connectivity"
    echo "  phase3   Add NIC to VyOS VM + configure eth2"
    echo "  phase4   Update WireGuard + test management access"
    echo "  phase5   Update /etc/hosts on both nodes"
    echo "  phase6   Lock down port 8006 on LAN interface"
    echo "  all      Run all phases sequentially"
    echo "  rollback Undo everything"
}

case "${1:-}" in
    phase1)   phase1 ;;
    phase2)   phase2 ;;
    phase3)   phase3 ;;
    phase4)   phase4 ;;
    phase5)   phase5 ;;
    phase6)   phase6 ;;
    all)
        phase1
        phase2
        phase3
        phase4
        phase5
        phase6
        echo ""
        ok "=========================================="
        ok "  Management isolation complete!"
        ok "=========================================="
        echo ""
        echo "  Proxmox UI: https://10.0.0.10:8006 (pve)"
        echo "              https://10.0.0.11:8006 (pve2)"
        echo "  Access via:  WireGuard VPN only"
        echo "  Emergency:   SSH still open on LAN IPs"
        echo ""
        ;;
    rollback) rollback ;;
    *)        usage ;;
esac
