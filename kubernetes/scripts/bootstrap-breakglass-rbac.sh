#!/usr/bin/env bash
# Bootstrap the breakglass ServiceAccount/Role/RoleBinding and generate its
# scoped kubeconfig for rollout_restart.
#
# NOT part of the ArgoCD-managed app tree — this is cluster-bootstrap
# tooling for an out-of-cluster consumer (breakglass-lxc), same category
# as bootstrap-secrets.sh.
#
# Prerequisites:
#   - kubectl configured for the target cluster (~/.kube/homelab-k3s.yaml)
#
# Usage (from the kubernetes/ directory):
#   ./scripts/bootstrap-breakglass-rbac.sh > ../services/breakglass/deploy/kubeconfig
# That path (services/breakglass/deploy/kubeconfig from repo root) is what
# ansible/deploy-breakglass.yml's "Deploy the scoped K8s kubeconfig" task
# defaults BREAKGLASS_KUBECONFIG_SRC to, and it's covered by .gitignore's
# bare `kubeconfig` pattern, so it won't be committed. Just run
# deploy-breakglass.yml afterwards to ship it to breakglass-lxc.

set -euo pipefail

NAMESPACE="uptime-kuma"
SA_NAME="breakglass"

echo "==> Applying breakglass RBAC (ServiceAccount/Role/RoleBinding)..." >&2
kubectl apply -f "$(dirname "${BASH_SOURCE[0]}")/bootstrap-breakglass-rbac.yaml" >&2

echo "==> Waiting for the ServiceAccount token Secret to populate..." >&2
kubectl -n "$NAMESPACE" wait --for=jsonpath='{.data.token}' secret/breakglass-token --timeout=30s >&2

CLUSTER_NAME=$(kubectl config view --minify -o jsonpath='{.clusters[0].name}')
SERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
CA_DATA=$(kubectl -n "$NAMESPACE" get secret breakglass-token -o jsonpath='{.data.ca\.crt}')
TOKEN=$(kubectl -n "$NAMESPACE" get secret breakglass-token -o jsonpath='{.data.token}' | base64 -d)

cat <<EOF
apiVersion: v1
kind: Config
clusters:
  - name: ${CLUSTER_NAME}
    cluster:
      server: ${SERVER}
      certificate-authority-data: ${CA_DATA}
contexts:
  - name: breakglass
    context:
      cluster: ${CLUSTER_NAME}
      namespace: ${NAMESPACE}
      user: breakglass
current-context: breakglass
users:
  - name: breakglass
    user:
      token: ${TOKEN}
EOF

echo "==> Done. kubeconfig written to stdout — redirect to" >&2
echo "    ../services/breakglass/deploy/kubeconfig, then run" >&2
echo "    ansible/deploy-breakglass.yml to deploy it to breakglass-lxc." >&2
