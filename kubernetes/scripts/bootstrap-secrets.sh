#!/usr/bin/env bash
# Bootstrap cluster secrets from SOPS-encrypted files
# Run this after installing ArgoCD but before apps sync
#
# Prerequisites:
#   - sops installed (brew install sops)
#   - GPG key imported (gpg --import sops-gpg-key.asc)
#   - kubectl configured for the target cluster
#
# Usage: ./scripts/bootstrap-secrets.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "==> Bootstrapping cluster secrets from SOPS-encrypted files"

# SOPS GPG key for ArgoCD KSOPS decryption (must be applied first)
echo "--> Applying argocd/sops-gpg-key secret..."
sops -d "$REPO_ROOT/infrastructure/argocd/secrets/sops-gpg-key.secret.yaml" | kubectl apply -f -

# ArgoCD GitHub App credentials
echo "--> Applying argocd/github-repo secret..."
sops -d "$REPO_ROOT/infrastructure/argocd/secrets/github-repo.secret.yaml" | kubectl apply -f -

# Cloudflare tunnel credentials
echo "--> Applying cloudflare-tunnel/cloudflared-credentials secret..."
sops -d "$REPO_ROOT/infrastructure/cloudflare-tunnel/secrets/cloudflared-credentials.secret.yaml" | kubectl apply -f -

# Personal backend secrets
if sops -d "$REPO_ROOT/personal/secrets/backend-secrets.secret.yaml" 2>/dev/null | grep -q 'PLACEHOLDER'; then
  echo "--> SKIPPING personal/backend-secrets (still has PLACEHOLDER values)"
  echo "    Edit with: sops personal/secrets/backend-secrets.secret.yaml"
else
  echo "--> Applying personal/backend-secrets secret..."
  kubectl create namespace personal --dry-run=client -o yaml | kubectl apply -f -
  sops -d "$REPO_ROOT/personal/secrets/backend-secrets.secret.yaml" | kubectl apply -f -
fi

# Newt tunnel credentials
if sops -d "$REPO_ROOT/infrastructure/newt/secrets/newt-credentials.secret.yaml" 2>/dev/null | grep -q 'PLACEHOLDER'; then
  echo "--> SKIPPING newt/newt-credentials (still has PLACEHOLDER values)"
  echo "    Edit with: sops infrastructure/newt/secrets/newt-credentials.secret.yaml"
  echo "    Then set NEWT_ID and NEWT_SECRET from a new Pangolin K3s site"
else
  echo "--> Applying newt/newt-credentials secret..."
  kubectl create namespace newt --dry-run=client -o yaml | kubectl apply -f -
  sops -d "$REPO_ROOT/infrastructure/newt/secrets/newt-credentials.secret.yaml" | kubectl apply -f -
fi

# Wiki.js DB credentials
echo "--> Applying wikijs/wikijs-secret secret..."
kubectl create namespace wikijs --dry-run=client -o yaml | kubectl apply -f -
sops -d "$REPO_ROOT/infrastructure/wikijs/secrets/wikijs-secret.secret.yaml" | kubectl apply -f -

echo ""
echo "==> Done! Secrets applied. ArgoCD should now be able to sync all apps."
echo ""
echo "To update a secret later:"
echo "  1. sops <path-to-secret.yaml>   # Edit in place (decrypts, opens editor, re-encrypts)"
echo "  2. git add && git commit && git push"
echo "  3. Re-run this script or: sops -d <file> | kubectl apply -f -"
