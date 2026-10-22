terraform {
  required_version = ">= 1.0"

  required_providers {
    authentik = {
      source  = "goauthentik/authentik"
      version = "~> 2024.12"
    }
  }
}

provider "authentik" {
  url   = var.authentik_url
  token = var.authentik_token
}
