#!/usr/bin/env bash
# Add your SSH public key to ubuntu@<first-control-plane> using the cluster API (kubeconfig).
# Uses kubectl debug node to run a one-off pod on the node with host filesystem access.
#
# Usage: ./scripts/k3s-node-add-ssh-key.sh [path-to-public-key]
# Default key: ~/.ssh/id_ed25519_homelab.pub
#
# Requires: KUBECONFIG pointing at the cluster (e.g. repo kubeconfig). You must be able to
# reach the API server (e.g. via Tailscale subnet router or VPN).

set -e
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KUBECONFIG="${KUBECONFIG:-$REPO_ROOT/kubeconfig}"
PUBKEY_FILE="${1:-$HOME/.ssh/id_ed25519_homelab.pub}"

if [[ ! -f "$KUBECONFIG" ]]; then
  echo "KUBECONFIG not found at $KUBECONFIG" >&2
  exit 1
fi
if [[ ! -f "$PUBKEY_FILE" ]]; then
  echo "Public key not found at $PUBKEY_FILE" >&2
  exit 1
fi

export KUBECONFIG
# First CP IP from kubeconfig (e.g. 10.10.10.11)
FIRST_CP_IP=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}' | sed -e 's|https://||' -e 's|:.*||')
# Node name that has this InternalIP (works without jq)
NODE_NAME=""
for name in $(kubectl get nodes -o jsonpath='{.items[*].metadata.name}'); do
  ip=$(kubectl get node "$name" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
  if [[ "$ip" == "$FIRST_CP_IP" ]]; then
    NODE_NAME="$name"
    break
  fi
done
if [[ -z "$NODE_NAME" ]]; then
  echo "Could not find node with InternalIP $FIRST_CP_IP" >&2
  exit 1
fi

echo "Cluster API: $FIRST_CP_IP (from kubeconfig)"
echo "Node: $NODE_NAME"
echo "Adding key from $PUBKEY_FILE to ubuntu@<node> via kubectl debug..."

KEY_B64=$(base64 < "$PUBKEY_FILE" | tr -d '\n')
CMD="mkdir -p /host/home/ubuntu/.ssh && echo $KEY_B64 | base64 -d >> /host/home/ubuntu/.ssh/authorized_keys && chown 1000:1000 /host/home/ubuntu/.ssh/authorized_keys /host/home/ubuntu/.ssh 2>/dev/null || true"

# Try with --profile=sysadmin first (write access to host fs); K3s may not support it
if kubectl debug "node/$NODE_NAME" --image=busybox:1.36 --target=node --profile=sysadmin --restart=Never -- sh -c "$CMD" 2>/dev/null; then
  echo "Ran with --profile=sysadmin"
else
  kubectl debug "node/$NODE_NAME" --image=busybox:1.36 --target=node --restart=Never -- sh -c "$CMD"
fi

# Clean up debug pod(s) for this node
sleep 2
kubectl get pods -A -o name | grep -E "node-debugger-${NODE_NAME}-|debug-${NODE_NAME}-" | while read -r p; do
  kubectl delete "$p" --wait=false 2>/dev/null || true
done

echo "Done. Test SSH: ./scripts/vps-k3s-join.sh"