#!/usr/bin/env bash
# Join the VPS to the existing K3s cluster using repo kubeconfig and SSH to first CP.
#
# Network: K3s nodes (10.10.10.x) are reached via VyOS (192.168.50.18). The VPS (Tailscale)
# reaches the lab via your Tailscale subnet router, which routes through VyOS to the K3s nodes.
#
# Usage:
#   ./scripts/vps-k3s-join.sh
#     Uses first CP from kubeconfig (10.10.10.11) for token fetch and join URL.
#     SSH to the first CP goes through VyOS (vyos@192.168.50.18); ensure ~/.ssh/config
#     has ProxyJump/ProxyCommand for 10.10.10.x via vyos@192.168.50.18.
#   ./scripts/vps-k3s-join.sh <FIRST_CP_IP>
#     Override the join URL host (default is kubeconfig server host).
#
# Jump host: SSH to the first CP goes through VyOS. Set in script or override with env:
#   VYOS_HOST=192.168.50.18  VYOS_USER=vyos  (optional) SSH_KEY=~/.ssh/id_ed25519_homelab

set -e
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KUBECONFIG="${REPO_ROOT}/kubeconfig"

VYOS_HOST="${VYOS_HOST:-192.168.50.18}"
VYOS_USER="${VYOS_USER:-vyos}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519_homelab}"
PROXY_CMD="ssh -F /dev/null -i ${SSH_KEY} -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new ${VYOS_USER}@${VYOS_HOST} nc %h %p"

if [[ ! -f "$KUBECONFIG" ]]; then
  echo "kubeconfig not found at $KUBECONFIG" >&2
  exit 1
fi

# First CP host from kubeconfig server URL (e.g. 10.10.10.11)
FIRST_CP_HOST=$(kubectl --kubeconfig="$KUBECONFIG" config view --minify -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null | sed -e 's|https://||' -e 's|:.*||')
if [[ -z "$FIRST_CP_HOST" ]]; then
  echo "Could not get server host from kubeconfig" >&2
  exit 1
fi

# Join URL host: optional arg, or same as kubeconfig (VPS reaches homelab via subnet router)
JOIN_HOST="${1:-$FIRST_CP_HOST}"
echo "First control plane (from kubeconfig): $FIRST_CP_HOST"
echo "Join URL (VPS will use this to reach the cluster): https://${JOIN_HOST}:6443"
echo "Jump host: ${VYOS_USER}@${VYOS_HOST}"

echo "Fetching node token from ubuntu@${FIRST_CP_HOST} (via VyOS)..."
# Use -F /dev/null so global SSH config (e.g. IdentityFile id_ecdsa_piv) is not used
K3S_TOKEN=$(ssh -F /dev/null -i "$SSH_KEY" -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new -o ProxyCommand="$PROXY_CMD" "ubuntu@${FIRST_CP_HOST}" 'sudo cat /var/lib/rancher/k3s/server/node-token')
if [[ -z "$K3S_TOKEN" ]]; then
  echo "Failed to get token" >&2
  exit 1
fi

cd "$REPO_ROOT/ansible"
ansible-playbook -i inventory-vps.ini vps-exit-node-k3s-cp.yml \
  -e "k3s_first_cp_url=https://${JOIN_HOST}:6443" \
  -e "k3s_token=${K3S_TOKEN}"
