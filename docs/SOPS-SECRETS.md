# SOPS Secrets Management

This repo uses [SOPS](https://github.com/getsops/sops) to encrypt secrets before committing to git.

## Setup

### Prerequisites

- SOPS installed: `brew install sops`
- GPG key imported (SOPS GitOps key: `F9C7B39DE2C2479CCA33C2702D63018142A3B959`)

### Configuration

The `.sops.yaml` file at the repo root defines encryption rules:

| Pattern | Description |
|---------|-------------|
| `*.enc.tfvars` | Encrypted Terraform variable files |
| `secrets/*.yaml` | Encrypted YAML secrets |
| `secrets/*.json` | Encrypted JSON secrets |
| `*.enc.env` | Encrypted environment files |

## Usage

### Decrypt All Terraform Secrets

```bash
./scripts/sops-decrypt.sh
```

This decrypts all `terraform.enc.tfvars` files to `terraform.tfvars` (which are gitignored).

### Manual Decrypt

```bash
# Decrypt to stdout
sops --decrypt infrastructure/terraform/terraform.enc.tfvars

# Decrypt to file
sops --decrypt infrastructure/terraform/terraform.enc.tfvars > infrastructure/terraform/terraform.tfvars
```

### Encrypt a New File

```bash
# Encrypt in-place (for files matching .sops.yaml patterns)
sops --encrypt --in-place path/to/secrets.enc.tfvars

# Or encrypt to a new file
sops --encrypt path/to/secrets.tfvars > path/to/secrets.enc.tfvars
```

### Edit Encrypted File

```bash
sops infrastructure/terraform/terraform.enc.tfvars
```

This decrypts to a temp file, opens your editor, then re-encrypts on save.

## Encrypted Files

| File | Contents |
|------|----------|
| `infrastructure/terraform/terraform.enc.tfvars` | Proxmox API token, VM password, SSH key |
| `infrastructure/terraform-k3s/terraform.enc.tfvars` | Proxmox API token, VM password, SSH keys |
| `infrastructure/terraform-vyos/terraform.enc.tfvars` | Proxmox API token |
| `infrastructure/terraform-authentik/terraform.enc.tfvars` | Authentik API token |
| `infrastructure/terraform-grafana/terraform.enc.tfvars` | Grafana service account token |

## Workflow

1. Clone repo
2. Run `./scripts/sops-decrypt.sh` to decrypt secrets
3. Run Terraform commands normally
4. If you update secrets, re-encrypt: `sops --encrypt --in-place file.enc.tfvars`
5. Commit the encrypted `.enc.tfvars` files (plaintext `.tfvars` are gitignored)

## Key Management

The GPG key `F9C7B39DE2C2479CCA33C2702D63018142A3B959` (SOPS GitOps) is used for encryption.

To add another key (e.g., for a team member), update `.sops.yaml` with their GPG fingerprint and re-encrypt all files:

```bash
# Update .sops.yaml with new key, then:
find infrastructure -name "*.enc.tfvars" -exec sops updatekeys {} \;
```
