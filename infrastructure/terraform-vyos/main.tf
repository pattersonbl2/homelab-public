terraform {
  required_version = ">= 1.0"

  backend "s3" {}

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.90"
    }
  }
}

provider "proxmox" {
  endpoint  = var.proxmox_api_url
  api_token = "${var.proxmox_api_token_id}=${var.proxmox_api_token_secret}"
  insecure  = var.proxmox_tls_insecure

  ssh {
    agent    = true
    username = var.proxmox_ssh_username
  }
}

locals {
  vyos_vm_id   = var.vyos_vm_id
  vyos_vm_name = var.vyos_vm_name
  vyos_node    = var.vyos_node

  # VyOS network configuration
  vyos_wan_bridge = var.vyos_wan_bridge
  vyos_lan_bridge = var.vyos_lan_bridge
  vyos_wan_ip     = var.vyos_wan_ip
  vyos_lan_ip     = var.vyos_lan_ip
}

# Reference existing VyOS ISO on Proxmox
# ISO file already uploaded to the specified node's storage
data "proxmox_virtual_environment_file" "vyos_iso" {
  datastore_id = var.vm_cloud_image_datastore
  node_name    = local.vyos_node
  content_type = "iso"
  file_name    = var.vyos_iso_filename
}

# VyOS Router VM
resource "proxmox_virtual_environment_vm" "vyos_router" {
  name      = local.vyos_vm_name
  node_name = local.vyos_node
  vm_id     = local.vyos_vm_id

  description = "VyOS Router - Lab Network Gateway"
  tags        = ["vyos", "router", "network"]

  on_boot = true
  started = true

  stop_on_destroy     = true
  timeout_shutdown_vm = 60
  timeout_stop_vm     = 60

  cpu {
    cores = var.vyos_cores
    type  = var.vyos_cpu_type
  }

  memory {
    dedicated = var.vyos_memory
  }

  # Boot from ISO for initial installation
  cdrom {
    file_id = data.proxmox_virtual_environment_file.vyos_iso.id
  }

  # Disk for VyOS installation
  disk {
    datastore_id = var.vm_storage_pool
    interface    = "scsi0"
    size         = var.vyos_disk_size
    file_format  = "raw"
  }

  # WAN interface - Connected to main network
  network_device {
    bridge  = local.vyos_wan_bridge
    model   = var.vyos_network_model
    vlan_id = null
  }

  # LAN interface - Connected to lab network bridge
  network_device {
    bridge  = local.vyos_lan_bridge
    model   = var.vyos_network_model
    vlan_id = null
  }

  vga {
    memory = 16
    type   = "std"
  }

  # Serial console for access
  serial_device {}

  lifecycle {
    ignore_changes = [
      cdrom,  # Don't recreate VM if ISO changes after install
      started # Don't force restart on apply
    ]
  }
}
