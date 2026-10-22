# TrueNAS SCALE – Dataset Terraform

Create and manage ZFS datasets on TrueNAS SCALE using Terraform (IaC).

**Requirements:** TrueNAS SCALE 25.10.1+, Terraform 1.0+, [bmanojlovic/truenas](https://registry.terraform.io/providers/bmanojlovic/truenas/latest) provider.

## 1. API key on TrueNAS

1. In TrueNAS: **System > API Keys**
2. **Add** – set a name and (optionally) an allow list so the key can only call `pool.dataset.*`
3. Copy the token; it is shown only once.

## 2. Configure

```bash
cd infrastructure/terraform-truenas
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars:
#   truenas_host       = "https://YOUR_TRUENAS_IP"
#   truenas_api_token  = "YOUR_TOKEN"
#   datasets           = ["pool/name", "pool/parent/child"]
```

## 3. Run

```bash
terraform init
terraform plan
terraform apply
```

## Variables

| Variable            | Description                    |
|---------------------|--------------------------------|
| `truenas_host`      | TrueNAS URL (HTTPS)            |
| `truenas_api_token` | API key from System > API Keys |
| `datasets`          | List of paths: `pool/name`     |

To add quotas or other options, extend `main.tf` and use the [provider docs](https://registry.terraform.io/providers/bmanojlovic/truenas/latest/docs/resources/pool_dataset) for `truenas_pool_dataset`.
