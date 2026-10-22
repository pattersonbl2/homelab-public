# Authentik Configuration via Terraform
# 
# This configures Authentik as the identity provider for Pangolin and other services.
#
# Prerequisites:
#   1. Complete Authentik initial setup at https://auth.vps.bp31app.com/if/flow/initial-setup/
#   2. Create an API token: Admin > System > Tokens > Create (with all permissions)
#   3. Set the token in terraform.tfvars or via TF_VAR_authentik_token
#
# Usage:
#   cd infrastructure/terraform-authentik
#   terraform init
#   terraform plan
#   terraform apply

# ─────────────────────────────────────────────────────────────────────────────
# Data Sources - Fetch existing Authentik resources
# ─────────────────────────────────────────────────────────────────────────────

data "authentik_flow" "default_authorization" {
  slug = "default-provider-authorization-implicit-consent"
}

data "authentik_flow" "default_invalidation" {
  slug = "default-provider-invalidation-flow"
}

data "authentik_certificate_key_pair" "generated" {
  name = "authentik Self-signed Certificate"
}

data "authentik_property_mapping_provider_scope" "openid" {
  managed = "goauthentik.io/providers/oauth2/scope-openid"
}

data "authentik_property_mapping_provider_scope" "email" {
  managed = "goauthentik.io/providers/oauth2/scope-email"
}

data "authentik_property_mapping_provider_scope" "profile" {
  managed = "goauthentik.io/providers/oauth2/scope-profile"
}

# ─────────────────────────────────────────────────────────────────────────────
# Pangolin Application & OAuth2 Provider
# ─────────────────────────────────────────────────────────────────────────────

resource "authentik_provider_oauth2" "pangolin" {
  name               = "Pangolin Provider"
  authorization_flow = data.authentik_flow.default_authorization.id
  invalidation_flow  = data.authentik_flow.default_invalidation.id
  client_type        = "confidential"
  client_id          = "pangolin"
  signing_key        = data.authentik_certificate_key_pair.generated.id

  allowed_redirect_uris = [
    { matching_mode = "strict", url = var.pangolin_redirect_uri }
  ]

  property_mappings = [
    data.authentik_property_mapping_provider_scope.openid.id,
    data.authentik_property_mapping_provider_scope.email.id,
    data.authentik_property_mapping_provider_scope.profile.id,
  ]

  sub_mode                   = "user_username"
  include_claims_in_id_token = true
  access_token_validity      = "minutes=10"
  refresh_token_validity     = "days=30"
}

resource "authentik_application" "pangolin" {
  name              = "Pangolin"
  slug              = "pangolin"
  protocol_provider = authentik_provider_oauth2.pangolin.id
  meta_launch_url   = "https://pangolin.${var.domain}"
  meta_description  = "Pangolin Tunnel Control Plane"

  open_in_new_tab = true
}

# ─────────────────────────────────────────────────────────────────────────────
# Groups for Access Control
# ─────────────────────────────────────────────────────────────────────────────

resource "authentik_group" "pangolin_admins" {
  name         = "pangolin-admins"
  is_superuser = false
}

resource "authentik_group" "pangolin_users" {
  name         = "pangolin-users"
  is_superuser = false
}

resource "authentik_group" "homelab_admins" {
  name         = "homelab-admins"
  is_superuser = false
}

# ─────────────────────────────────────────────────────────────────────────────
# Proxy Providers for Traefik Forward Auth
# These protect services exposed through Pangolin/Traefik
# ─────────────────────────────────────────────────────────────────────────────

# Pi-hole DNS Admin
resource "authentik_provider_proxy" "pihole" {
  name                  = "Pi-hole Provider"
  authorization_flow    = data.authentik_flow.default_authorization.id
  invalidation_flow     = data.authentik_flow.default_invalidation.id
  external_host         = "https://dns.${var.domain}"
  mode                  = "forward_single"
  access_token_validity = "hours=24"
}

resource "authentik_application" "pihole" {
  name              = "Pi-hole DNS"
  slug              = "pihole"
  protocol_provider = authentik_provider_proxy.pihole.id
  meta_launch_url   = "https://dns.${var.domain}/admin/"
  meta_description  = "Pi-hole DNS Admin"
  meta_icon         = "https://pi-hole.net/wp-content/uploads/2016/12/Vortex-R.png"
  open_in_new_tab   = true
}

# VPS Metrics (Node Exporter)
resource "authentik_provider_proxy" "vps_metrics" {
  name                  = "VPS Metrics Provider"
  authorization_flow    = data.authentik_flow.default_authorization.id
  invalidation_flow     = data.authentik_flow.default_invalidation.id
  external_host         = "https://vps-metrics.${var.domain}"
  mode                  = "forward_single"
  access_token_validity = "hours=24"
}

resource "authentik_application" "vps_metrics" {
  name              = "VPS Metrics"
  slug              = "vps-metrics"
  protocol_provider = authentik_provider_proxy.vps_metrics.id
  meta_launch_url   = "https://vps-metrics.${var.domain}"
  meta_description  = "VPS Node Exporter Metrics"
  open_in_new_tab   = true
}

# Pangolin Admin (protect the control plane itself)
resource "authentik_provider_proxy" "pangolin_admin" {
  name                  = "Pangolin Admin Provider"
  authorization_flow    = data.authentik_flow.default_authorization.id
  invalidation_flow     = data.authentik_flow.default_invalidation.id
  external_host         = "https://pangolin.${var.domain}"
  mode                  = "forward_single"
  access_token_validity = "hours=24"
}

# ─────────────────────────────────────────────────────────────────────────────
# ArgoCD Application & OAuth2 Provider
# ─────────────────────────────────────────────────────────────────────────────

resource "authentik_provider_oauth2" "argocd" {
  name               = "ArgoCD Provider"
  authorization_flow = data.authentik_flow.default_authorization.id
  invalidation_flow  = data.authentik_flow.default_invalidation.id
  client_type        = "confidential"
  client_id          = "argocd"
  signing_key        = data.authentik_certificate_key_pair.generated.id

  allowed_redirect_uris = [
    { matching_mode = "strict", url = "https://argocd.vps.bp31app.com/auth/callback" }
  ]

  property_mappings = [
    data.authentik_property_mapping_provider_scope.openid.id,
    data.authentik_property_mapping_provider_scope.email.id,
    data.authentik_property_mapping_provider_scope.profile.id,
  ]

  sub_mode                   = "user_email"
  include_claims_in_id_token = true
  access_token_validity      = "minutes=10"
  refresh_token_validity     = "days=30"
}

resource "authentik_application" "argocd" {
  name              = "ArgoCD"
  slug              = "argocd"
  protocol_provider = authentik_provider_oauth2.argocd.id
  meta_launch_url   = "https://argocd.vps.bp31app.com"
  meta_description  = "GitOps Continuous Delivery"
  open_in_new_tab   = true
}

# ─────────────────────────────────────────────────────────────────────────────
# Wiki.js Application & OAuth2 Provider
# ─────────────────────────────────────────────────────────────────────────────

resource "authentik_provider_oauth2" "wikijs" {
  name               = "Wiki.js Provider"
  authorization_flow = data.authentik_flow.default_authorization.id
  invalidation_flow  = data.authentik_flow.default_invalidation.id
  client_type        = "confidential"
  client_id          = "wikijs"
  signing_key        = data.authentik_certificate_key_pair.generated.id

  allowed_redirect_uris = [
    { matching_mode = "strict", url = "http://wiki.local.bp31app.com/login/oidc-authentik/callback" }
  ]

  property_mappings = [
    data.authentik_property_mapping_provider_scope.openid.id,
    data.authentik_property_mapping_provider_scope.email.id,
    data.authentik_property_mapping_provider_scope.profile.id,
  ]

  sub_mode                   = "user_email"
  include_claims_in_id_token = true
  access_token_validity      = "minutes=10"
  refresh_token_validity     = "days=30"
}

resource "authentik_application" "wikijs" {
  name              = "Wiki.js"
  slug              = "wikijs"
  protocol_provider = authentik_provider_oauth2.wikijs.id
  meta_launch_url   = "http://wiki.local.bp31app.com"
  meta_description  = "Homelab documentation wiki"
  open_in_new_tab   = true
}

# ─────────────────────────────────────────────────────────────────────────────
# Outputs - Values needed for Pangolin configuration
# ─────────────────────────────────────────────────────────────────────────────

output "pangolin_oauth2_config" {
  description = "OAuth2 configuration values for Pangolin identity provider"
  value = {
    client_id         = authentik_provider_oauth2.pangolin.client_id
    client_secret     = authentik_provider_oauth2.pangolin.client_secret
    authorization_url = "${var.authentik_url}/application/o/authorize/"
    token_url         = "${var.authentik_url}/application/o/token/"
    userinfo_url      = "${var.authentik_url}/application/o/userinfo/"
  }
  sensitive = true
}

output "argocd_client_id" {
  description = "ArgoCD OAuth2 client ID"
  value       = authentik_provider_oauth2.argocd.client_id
}

output "argocd_client_secret" {
  description = "ArgoCD OAuth2 client secret (store in argocd-secret)"
  value       = authentik_provider_oauth2.argocd.client_secret
  sensitive   = true
}

output "pangolin_setup_instructions" {
  description = "Instructions for configuring Pangolin"
  value       = <<-EOT
    
    ═══════════════════════════════════════════════════════════════════════════
    Pangolin Identity Provider Configuration
    ═══════════════════════════════════════════════════════════════════════════
    
    1. Go to Pangolin: https://pangolin.${var.domain}
    2. Navigate to: Server Admin > Identity Providers > Add Identity Provider
    3. Select: OAuth2/OIDC
    
    Enter these values:
    
      Name:              Authentik
      Auto Provision:    ✓ Enabled
      Client ID:         ${authentik_provider_oauth2.pangolin.client_id}
      Client Secret:     (run 'terraform output -raw pangolin_oauth2_config | jq -r .client_secret')
      Authorization URL: ${var.authentik_url}/application/o/authorize/
      Token URL:         ${var.authentik_url}/application/o/token/
    
    Advanced Settings:
      Subject Mode:      Based on the User's username
      Scopes:            openid profile email
    
    4. After creating, note the Redirect URI shown in Pangolin
    5. If different from current, update var.pangolin_redirect_uri and re-apply
    
    ═══════════════════════════════════════════════════════════════════════════
  EOT
}

output "wikijs_client_id" {
  description = "Wiki.js OAuth2 client ID"
  value       = authentik_provider_oauth2.wikijs.client_id
}

output "wikijs_client_secret" {
  description = "Wiki.js OAuth2 client secret (store in wikijs SOPS secret)"
  value       = authentik_provider_oauth2.wikijs.client_secret
  sensitive   = true
}
