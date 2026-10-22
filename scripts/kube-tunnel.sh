#!/usr/bin/env bash
# kube-tunnel.sh - Set up kubectl access to K3s cluster via SSH tunnel through VyOS
#
# VyOS (192.168.50.18) is reachable from the Mac and has a route to 10.10.10.0/24.
# This script tunnels the K3s API (10.10.10.11:6443) to localhost:6443.
#
# Usage:
#   scripts/kube-tunnel.sh          # Start tunnel (foreground; Ctrl-C to stop)
#   scripts/kube-tunnel.sh -d       # Start tunnel in background (daemon mode)
#   scripts/kube-tunnel.sh stop     # Stop background tunnel
#   scripts/kube-tunnel.sh status   # Check tunnel status
#   scripts/kube-tunnel.sh refresh  # Re-fetch kubeconfig from cluster (needs route or active tunnel on port 10022)
#
# Kubeconfig is saved to ~/.kube/homelab-k3s.yaml
# Add to shell profile:  export KUBECONFIG=~/.kube/homelab-k3s.yaml

set -euo pipefail

VYOS_HOST="192.168.50.18"
VYOS_USER="vyos"
K3S_CP="10.10.10.11"
K3S_USER="bp31"
SSH_KEY="$HOME/.ssh/id_ed25519_homelab"
LOCAL_PORT="6443"
SSH_PORT="10022"        # local port for SSH tunnel to CP node
KUBECONFIG_PATH="$HOME/.kube/homelab-k3s.yaml"
PID_FILE="/tmp/kube-tunnel.pid"

SSH_OPTS="-o StrictHostKeyChecking=accept-new -o BatchMode=yes -o IdentitiesOnly=yes -i $SSH_KEY"

tunnel_running() {
    [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null
}

start_tunnel() {
    local daemon="${1:-}"

    if tunnel_running; then
        echo "Tunnel already running (PID $(cat "$PID_FILE"))"
        echo "KUBECONFIG=$KUBECONFIG_PATH"
        return 0
    fi

    if [ ! -f "$KUBECONFIG_PATH" ]; then
        echo "No kubeconfig found at $KUBECONFIG_PATH"
        echo "Run with 'refresh' first (while route is active or after manually connecting)"
        exit 1
    fi

    if [ "$daemon" = "-d" ]; then
        ssh $SSH_OPTS -f -N \
            -L "${LOCAL_PORT}:${K3S_CP}:6443" \
            "${VYOS_USER}@${VYOS_HOST}"
        # Find the PID of the background ssh process
        sleep 0.5
        pgrep -f "ssh.*${LOCAL_PORT}:${K3S_CP}:6443" | head -1 > "$PID_FILE"
        echo "Tunnel started (PID $(cat "$PID_FILE"))"
        echo ""
        echo "  export KUBECONFIG=$KUBECONFIG_PATH"
        echo ""
        echo "Stop with: $0 stop"
    else
        echo "Tunnel open: localhost:${LOCAL_PORT} -> ${K3S_CP}:6443 via VyOS"
        echo "export KUBECONFIG=$KUBECONFIG_PATH"
        echo "(Ctrl-C to close)"
        echo ""
        ssh $SSH_OPTS -N \
            -L "${LOCAL_PORT}:${K3S_CP}:6443" \
            "${VYOS_USER}@${VYOS_HOST}"
    fi
}

stop_tunnel() {
    if tunnel_running; then
        kill "$(cat "$PID_FILE")" 2>/dev/null && echo "Tunnel stopped"
        rm -f "$PID_FILE"
    else
        # Try pkill as fallback
        pkill -f "ssh.*${LOCAL_PORT}:${K3S_CP}:6443" 2>/dev/null && echo "Tunnel stopped" || echo "No tunnel running"
    fi
}

refresh_kubeconfig() {
    echo "Fetching kubeconfig from ${K3S_CP}..."

    # Open a temporary SSH port forward for the CP node's SSH port
    ssh $SSH_OPTS -f -N \
        -L "${SSH_PORT}:${K3S_CP}:22" \
        "${VYOS_USER}@${VYOS_HOST}" 2>/dev/null || true
    sleep 1

    mkdir -p "$HOME/.kube"
    ssh $SSH_OPTS -p "$SSH_PORT" "${K3S_USER}@localhost" \
        "sudo cat /etc/rancher/k3s/k3s.yaml" 2>/dev/null \
        | sed "s|https://127.0.0.1:6443|https://localhost:${LOCAL_PORT}|g" \
        > "$KUBECONFIG_PATH"
    chmod 600 "$KUBECONFIG_PATH"

    # Kill the temporary SSH tunnel
    pkill -f "ssh.*${SSH_PORT}:${K3S_CP}:22" 2>/dev/null || true

    echo "Kubeconfig saved to $KUBECONFIG_PATH"
}

case "${1:-start}" in
    start|-d)
        start_tunnel "${1:-}"
        ;;
    stop)
        stop_tunnel
        ;;
    status)
        if tunnel_running; then
            echo "Tunnel running (PID $(cat "$PID_FILE"))"
        else
            echo "Tunnel not running"
        fi
        echo "KUBECONFIG=$KUBECONFIG_PATH"
        ;;
    refresh)
        refresh_kubeconfig
        ;;
    *)
        echo "Usage: $0 [start|-d|stop|status|refresh]"
        exit 1
        ;;
esac
