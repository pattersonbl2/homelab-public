# Authentik Terraform Configuration

Manages Authentik identity provider configuration as infrastructure-as-code.

## What This Configures

- **Pangolin OAuth2 Provider** - OIDC provider for Pangolin SSO
- **Pangolin Application** - Application entry in Authentik
- **Access Control Groups** - `pangolin-admins`, `pangolin-users`, `homelab-admins`

## Prerequisites

1. **Complete Authentik initial setup** at `https://auth.vps.bp31app.com/if/flow/initial-setup/`
2. **Create an API token**:
   - Go to Admin > System > Tokens
   - Create a new token with appropriate permissions
   - Save the token value securely

## Usage

```bash
cd infrastructure/terraform-authentik

# Copy and configure variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your API token

# Initialize and apply
terraform init
terraform plan
terraform apply
```

## Environment Variables Alternative

Instead of `terraform.tfvars`, you can use environment variables:

```bash
export TF_VAR_authentik_token="your-api-token"
terraform apply
```

## Outputs

After apply, Terraform outputs the configuration values needed for Pangolin:

```bash
# View setup instructions
terraform output pangolin_setup_instructions

# Get client secret (sensitive)
terraform output -raw pangolin_oauth2_config | jq -r .client_secret
```

## Updating Pangolin Redirect URI

After configuring the identity provider in Pangolin:

1. Note the Redirect URI shown in Pangolin
2. Update `terraform.tfvars`:
   ```hcl
   pangolin_redirect_uri = "https://pangolin.vps.bp31app.com/auth/idp/X/oidc/callback"
   ```
3. Re-apply: `terraform apply`

## Adding More Applications

To add SSO for additional services, create new provider/application pairs in `main.tf`:

```hcl
resource "authentik_provider_oauth2" "my_app" {
  name               = "My App Provider"
  authorization_flow = data.authentik_flow.default_authorization.id
  # ... configuration
}

resource "authentik_application" "my_app" {
  name              = "My App"
  slug              = "my-app"
  protocol_provider = authentik_provider_oauth2.my_app.id
  # ... configuration
}
```

## Proxy Provider for Traefik Forward Auth

For services that don't support OIDC natively, use a proxy provider:

```hcl
resource "authentik_provider_proxy" "protected_service" {
  name               = "Protected Service"
  authorization_flow = data.authentik_flow.default_authorization.id
  external_host      = "https://service.vps.bp31app.com"
  mode               = "forward_single"
}
```

## State Management

State is stored locally by default. For team collaboration, consider:

- GCS backend (like other terraform directories)
- Terraform Cloud
- S3 backend
