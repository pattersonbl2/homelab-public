#!/usr/bin/env bash
# Decrypt all SOPS-encrypted terraform.tfvars files
# Usage: ./scripts/sops-decrypt.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

find "$REPO_ROOT/infrastructure" -name "terraform.enc.tfvars" -type f | while read -r enc_file; do
  dir=$(dirname "$enc_file")
  dec_file="$dir/terraform.tfvars"
  
  echo "Decrypting: $enc_file -> $dec_file"
  sops --decrypt "$enc_file" > "$dec_file"
done

echo "Done. Decrypted tfvars files are gitignored and safe to use."
