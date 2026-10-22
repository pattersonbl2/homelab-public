terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

variable "cloudflare_api_token" {
  type      = string
  sensitive = true
}

variable "ark31_api_token" {
  type      = string
  sensitive = true
}

variable "ark31_zone_id" {
  type    = string
  default = "08a8a27a0d695108dd373bac560fc7e3"
}

variable "tunnel_api_token" {
  type        = string
  sensitive   = true
  description = "API token with Account > Cloudflare Tunnel > Edit permission"
}

variable "account_id" {
  type    = string
  default = "27626e58ff9ec80893677fc6bafa1dce"
}

# Second provider alias with tunnel permissions
provider "cloudflare" {
  alias     = "tunnel"
  api_token = var.tunnel_api_token
}

provider "cloudflare" {
  alias     = "ark31"
  api_token = var.ark31_api_token
}

variable "zone_id" {
  type    = string
  default = "bc45b570625380601a4eefaaec6a2722"
}

variable "tunnel_id" {
  type    = string
  default = "70b3f873-7237-472c-ad5d-e4c728107425"
}

# Update wildcard to route through Cloudflare proxy + tunnel
# Previously pointed to bp31app.com (unproxied) — didn't cover k8s-learn subdomains
resource "cloudflare_record" "wildcard_import" {
  zone_id = var.zone_id
  name    = "*"
  type    = "CNAME"
  content = "${var.tunnel_id}.cfargotunnel.com"
  proxied = true
  ttl     = 1

  lifecycle {
    # Import existing record — id from Cloudflare: 09af3dd60e86370030095fee3fdbf367
    prevent_destroy = false
  }
}

output "wildcard_hostname" {
  value = cloudflare_record.wildcard_import.hostname
}

# Tunnel ingress rules — fully code-managed, no dashboard needed
resource "cloudflare_zero_trust_tunnel_cloudflared_config" "homelab" {
  provider   = cloudflare.tunnel
  account_id = var.account_id
  tunnel_id  = var.tunnel_id

  config {
    # WARP routing for subnet access — exists in live tunnel state; declared
    # here so `apply` preserves it instead of disabling it (was undeclared drift).
    warp_routing {
      enabled = true
    }

    # SECURITY 2026-07-09: argocd.bp31app.com and api.kube.bp31app.com removed.
    # ArgoCD was served straight to the internet (real login page, no gate),
    # bypassing the intended Pangolin/Authentik path at argocd.vps.bp31app.com.
    # The Kubernetes API should never be internet-reachable — use WireGuard for
    # remote kubectl. Both are now reachable only via LAN / WireGuard / Pangolin.

    # n8n webhook only — VM 110 Docker Traefik, n8n UI stays internal
    ingress_rule {
      hostname = "learn-webhook.bp31app.com"
      service  = "http://192.168.50.97:80"
      origin_request {
        http_host_header = "n8n.local.bp31app.com"
      }
    }

    # Break-glass MCP endpoint — direct to breakglass-lxc, bypasses K3s Traefik
    ingress_rule {
      hostname = "ops.bp31app.com"
      service  = "http://192.168.50.46:8787"
    }

    # Jellyfin — direct to jellyfin-lxc, bypasses K3s Traefik. Public exposure
    # requested 2026-08-02 for remote family access via Quick Connect; gated
    # only by Jellyfin's own login/brute-force lockout, no additional Access layer.
    ingress_rule {
      hostname = "jellyfin.bp31app.com"
      service  = "http://192.168.50.31:8096"
    }

    # Jellyseerr — direct to media-lxc, bypasses K3s Traefik
    ingress_rule {
      hostname = "requests.bp31app.com"
      service  = "http://192.168.50.30:5055"
    }

    # Gitea — direct to gitea-lxc, bypasses K3s Traefik (which doesn't know about Gitea)
    ingress_rule {
      hostname = "gitea.bp31app.com"
      service  = "http://192.168.50.44:3000"
    }

    # Wildcard catch-all — everything else goes through K3s Traefik
    ingress_rule {
      hostname = "*.bp31app.com"
      service  = "http://traefik.traefik.svc.cluster.local:80"
    }

    # Required catch-all (no hostname = default)
    ingress_rule {
      service = "http_status:404"
    }
  }
}

output "tunnel_ingress_rules" {
  value = length(cloudflare_zero_trust_tunnel_cloudflared_config.homelab.config[0].ingress_rule)
}

# ark31.info — Gmail MX records
locals {
  gmail_mx = [
    { priority = 1, content = "ASPMX.L.GOOGLE.COM" },
    { priority = 5, content = "ALT1.ASPMX.L.GOOGLE.COM" },
    { priority = 5, content = "ALT2.ASPMX.L.GOOGLE.COM" },
    { priority = 10, content = "ALT3.ASPMX.L.GOOGLE.COM" },
    { priority = 10, content = "ALT4.ASPMX.L.GOOGLE.COM" },
  ]
}

resource "cloudflare_record" "ark31_mx" {
  provider = cloudflare.ark31
  for_each = { for r in local.gmail_mx : r.content => r }

  zone_id  = var.ark31_zone_id
  name     = "@"
  type     = "MX"
  content  = each.value.content
  priority = each.value.priority
  ttl      = 1
}

resource "cloudflare_record" "ark31_spf" {
  provider = cloudflare.ark31
  zone_id  = var.ark31_zone_id
  name     = "@"
  type     = "TXT"
  content  = "v=spf1 include:_spf.google.com ~all"
  ttl      = 1
}

resource "cloudflare_record" "ark31_dkim" {
  provider = cloudflare.ark31
  zone_id  = var.ark31_zone_id
  name     = "google._domainkey"
  type     = "TXT"
  content  = "v=DKIM1; k=rsa; p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEArXsMBSjKmKoBrGNoPzm9rMTX0OxFobcIxNcS/xDZZJDusgbVIdEXyRqK4vO20T66g11UK9sFI+E9o5N4B25/03v9OzdU/uCxpEBDILqTLhf+hULQ3w9tJV3a4NU11LB1hl+VeDzfU2FjP6ZZe6JWBiWUsfO14B9OM8ZSP991xMyJRV1eU8w9xXYOPmsruDoSctx+vDK6sbz7a2cw50sXhO3qq6p+vgL2HB38HzDXAcMJk/V22eUr7itJvubtxQHsVKwE/vp5XAindrtTxvamyivkOaVPChbZyH8SARZgFyhwgx5kC1SX8HPeMukbW6+b7/1Us4k4qbTOQqn1aNdylQIDAQAB"
  ttl      = 1
}

resource "cloudflare_record" "ark31_dmarc" {
  provider = cloudflare.ark31
  zone_id  = var.ark31_zone_id
  name     = "_dmarc"
  type     = "TXT"
  content  = "v=DMARC1; p=quarantine; rua=mailto:bpatterson@ark31.info"
  ttl      = 1
}

# Google Workspace custom URLs
locals {
  google_workspace_cnames = {
    mail     = "mail"
    calendar = "calendar"
    drive    = "drive"
    groups   = "groups"
  }
}

resource "cloudflare_record" "ark31_gws_cnames" {
  provider = cloudflare.ark31
  for_each = local.google_workspace_cnames

  zone_id = var.ark31_zone_id
  name    = each.value
  type    = "CNAME"
  content = "ghs.googlehosted.com"
  ttl     = 1
}
