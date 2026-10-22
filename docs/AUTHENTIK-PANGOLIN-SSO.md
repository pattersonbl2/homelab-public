# Authentik + Pangolin SSO Integration

This guide configures Authentik as the identity provider for Pangolin, enabling SSO login for all Pangolin users.

## Prerequisites

- Authentik deployed and running at `https://auth.vps.bp31app.com`
- Pangolin deployed and running at `https://pangolin.vps.bp31app.com`
- Admin access to both systems

## Quick Setup with Terraform (Recommended)

The easiest way to configure Authentik is via Terraform:

```bash
cd infrastructure/terraform-authentik

# Copy and configure
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your Authentik API token

# Apply
terraform init
terraform apply

# View Pangolin configuration instructions
terraform output pangolin_setup_instructions
```

See [infrastructure/terraform-authentik/README.md](../infrastructure/terraform-authentik/README.md) for details.

---

## Manual Setup

If you prefer manual configuration, follow these steps:

## Step 1: Create Authentik Application

1. Log in to Authentik admin at `https://auth.vps.bp31app.com/if/admin/`

2. Navigate to **Applications** → **Applications** → **Create with Provider**

3. Configure the application:
   - **Name**: `Pangolin`
   - **Slug**: `pangolin`
   - **Provider Type**: `OAuth2/OpenID Provider`

4. Configure the provider:
   - **Name**: `Pangolin Provider`
   - **Authorization flow**: `default-provider-authorization-implicit-consent`
   - **Client type**: `Confidential`
   - **Redirect URIs**: `https://temp.temp` (will update later)
   - **Signing Key**: Select any available key (or create one)
   - **Subject mode**: `Based on the User's username`

5. Click **Create**

6. **Save these values** - you'll need them for Pangolin:
   - Client ID
   - Client Secret

## Step 2: Configure Pangolin Identity Provider

1. Log in to Pangolin at `https://pangolin.vps.bp31app.com`

2. Navigate to **Server Admin** → **Identity Providers** → **Add Identity Provider**

3. Select **OAuth2/OIDC** as the provider type

4. Configure General Information:
   - **Name**: `Authentik`
   - **Auto Provision Users**: ✅ Enable (recommended)

5. Configure OAuth2/OIDC Settings:
   | Field | Value |
   |-------|-------|
   | Client ID | `<from Authentik>` |
   | Client Secret | `<from Authentik>` |
   | Authorization URL | `https://auth.vps.bp31app.com/application/o/authorize/` |
   | Token URL | `https://auth.vps.bp31app.com/application/o/token/` |

6. Configure Advanced Settings:
   - **Subject Mode**: `Based on the User's username`
   - **Scopes**: `openid profile email`

7. Click **Create Identity Provider**

8. **Copy the Redirect URI** shown (e.g., `https://pangolin.vps.bp31app.com/auth/idp/1/oidc/callback`)

## Step 3: Update Authentik Redirect URI

1. Go back to Authentik admin at `https://auth.vps.bp31app.com/if/admin/`

2. Navigate to **Applications** → **Providers** → **Pangolin Provider** → **Edit**

3. Update **Redirect URIs** with the value from Pangolin:
   ```
   https://pangolin.vps.bp31app.com/auth/idp/1/oidc/callback
   ```

4. Click **Update**

## Step 4: Test the Integration

1. Log out of Pangolin

2. On the Pangolin login page, click **Login with Authentik**

3. You should be redirected to Authentik to authenticate

4. After successful authentication, you'll be redirected back to Pangolin

## Optional: Auto-Provisioning with Groups

For advanced access control, configure group-based provisioning:

### In Authentik:

1. Create groups for Pangolin access:
   - `pangolin-admin` - Server administrators
   - `pangolin-users` - Regular users

2. Assign users to appropriate groups

### In Pangolin:

1. Edit the Authentik identity provider

2. Enable **Auto Provision Users**

3. Configure JMESPath expressions for role mapping (if needed)

## Troubleshooting

### Login redirects fail

- Verify the Redirect URI in Authentik matches exactly what Pangolin provides
- Check that both services are accessible from the browser
- Ensure Authentik's signing key is properly configured

### Users not provisioned

- Verify "Auto Provision Users" is enabled in Pangolin
- Check that the user has the required claims (email, username)
- Review Pangolin logs: `docker logs pangolin`

### Token errors

- Ensure Client ID and Client Secret match between systems
- Verify the Token URL is correct
- Check Authentik logs: `docker logs authentik-server`

## Network Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         User Browser                             │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                          Traefik                                 │
│         (routes to Pangolin or Authentik based on host)         │
└─────────────────────────────────────────────────────────────────┘
           │                                    │
           ▼                                    ▼
┌─────────────────────┐              ┌─────────────────────┐
│      Pangolin       │──── OIDC ───▶│      Authentik      │
│ pangolin.vps.bp31   │◀── tokens ──│  auth.vps.bp31      │
│     app.com         │              │     app.com         │
└─────────────────────┘              └─────────────────────┘
```

## Related Documentation

- [Authentik Pangolin Integration](https://docs.goauthentik.io/integrations/services/pangolin/)
- [Pangolin Identity Providers](https://docs.pangolin.net/manage/identity-providers/openid-connect)
