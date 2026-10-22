#!/bin/bash
# Apply Grafana Terraform config via kubectl port-forward
# Usage: ./apply.sh [plan|apply|destroy]

set -e

KUBECONFIG="${KUBECONFIG:-$HOME/.kube/homelab-k3s.yaml}"
ACTION="${1:-plan}"

echo "Starting port-forward to Grafana..."
# Tunnel through pve directly to Grafana ClusterIP (avoids kubectl + Pangolin auth issues)
ssh -f -N -L 3000:10.43.148.181:80 root@192.168.50.176
PF_PID=$!
trap "kill $PF_PID 2>/dev/null" EXIT

sleep 3

echo "Running terraform $ACTION..."
terraform "$ACTION"
