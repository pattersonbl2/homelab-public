# TrueNAS SCALE dataset management (IaC)
# Requires TrueNAS SCALE 25.10.1+ and an API key (System > API Keys).
# Provider: https://registry.terraform.io/providers/bmanojlovic/truenas/latest

terraform {
  required_version = ">= 1.0"

  backend "s3" {}

  required_providers {
    truenas = {
      source  = "bmanojlovic/truenas"
      version = "~> 0.0.34"
    }
  }
}

provider "truenas" {
  host  = var.truenas_host
  token = var.truenas_api_token
}

# Example: create datasets from a list
resource "truenas_pool_dataset" "datasets" {
  for_each = toset(var.datasets)

  # Full path: pool/name or pool/parent/child
  name = each.value
  type = "FILESYSTEM"

  # Optional: quota in bytes (e.g. 1073741824 = 1 GiB)
  # quota = 1073741824
}

# ---------- Backup datasets ----------

resource "truenas_pool_dataset" "backup" {
  name = "media/backup"
  type = "FILESYSTEM"
}

resource "truenas_pool_dataset" "backup_docker" {
  name       = "media/backup/docker"
  type       = "FILESYSTEM"
  depends_on = [truenas_pool_dataset.backup]
}

resource "truenas_pool_dataset" "backup_db" {
  name       = "media/backup/db"
  type       = "FILESYSTEM"
  depends_on = [truenas_pool_dataset.backup]
}

resource "truenas_pool_dataset" "backup_k3s" {
  name       = "media/backup/k3s"
  type       = "FILESYSTEM"
  depends_on = [truenas_pool_dataset.backup]
}

# ---------- Backup NFS shares ----------

resource "truenas_sharing_nfs" "backup_docker" {
  path         = "/mnt/media/backup/docker"
  comment      = "Docker volume backups (homelab-1)"
  hosts        = var.backup_docker_client_ips
  maproot_user  = "root"
  maproot_group = "root"
  depends_on   = [truenas_pool_dataset.backup_docker]
}

resource "truenas_sharing_nfs" "backup_db" {
  path          = "/mnt/media/backup/db"
  comment       = "Database backups (db-1 unprivileged LXC via pve2 bind mount)"
  hosts         = var.backup_db_client_ips
  mapall_user   = "root"
  mapall_group  = "root"
  depends_on    = [truenas_pool_dataset.backup_db]
}

resource "truenas_sharing_nfs" "backup_k3s" {
  path         = "/mnt/media/backup/k3s"
  comment      = "K3s Longhorn backups"
  networks     = [var.backup_k3s_client_network]
  maproot_user  = "root"
  maproot_group = "root"
  depends_on   = [truenas_pool_dataset.backup_k3s]
}
