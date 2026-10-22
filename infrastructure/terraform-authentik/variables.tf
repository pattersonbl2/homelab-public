variable "authentik_url" {
  description = "URL of the Authentik instance"
  type        = string
  default     = "https://auth.vps.bp31app.com"
}

variable "authentik_token" {
  description = "API token for Authentik (create in Admin > System > Tokens)"
  type        = string
  sensitive   = true
}

variable "pangolin_redirect_uri" {
  description = "Redirect URI from Pangolin identity provider config (set after initial Pangolin setup)"
  type        = string
  default     = "https://pangolin.vps.bp31app.com/auth/idp/1/oidc/callback"
}

variable "domain" {
  description = "Base domain for services"
  type        = string
  default     = "vps.bp31app.com"
}
