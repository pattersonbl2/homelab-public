# Proxmox VM Module - Main
# Reusable module for creating VMs on Proxmox with the BPG provider

terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.90"
    }
  }
}

resource "proxmox_virtual_environment_vm" "vm" {
  name        = var.vm_name
  node_name   = var.proxmox_node
  vm_id       = var.vm_id
  description = var.description

  tags            = var.tags
  stop_on_destroy = var.stop_on_destroy
  machine         = var.machine_type

  # CPU Configuration
  cpu {
    cores = var.cores
    type  = var.cpu_type
  }

  # Memory Configuration
  memory {
    dedicated = var.memory
  }

  # VGA Configuration
  vga {
    memory    = 64
    type      = "std"
    clipboard = "vnc"
  }

  # Disk Configuration
  disk {
    datastore_id = var.storage_pool
    file_id      = var.cloud_image_id
    interface    = "${var.disk_interface}0"
    discard      = "on"
    size         = var.disk_size
  }

  # Network Configuration
  network_device {
    bridge = var.bridge
    model  = var.network_model
  }

  # PCIe passthrough devices (use mapping for API token compatibility)
  dynamic "hostpci" {
    for_each = { for idx, dev in var.hostpci_devices : idx => dev }
    content {
      device  = "hostpci${hostpci.key}"
      id      = hostpci.value.mapping == null ? hostpci.value.id : null
      mapping = hostpci.value.mapping
      pcie    = hostpci.value.pcie
      rombar  = hostpci.value.rombar
      xvga    = hostpci.value.x_vga
    }
  }

  # QEMU Agent
  agent {
    enabled = var.agent_enabled
  }

  # Cloud-init Configuration
  initialization {
    datastore_id = var.storage_pool

    # Dynamic IP configuration based on use_dhcp
    ip_config {
      ipv4 {
        address = var.use_dhcp ? "dhcp" : "${var.static_ip}/${var.subnet_mask}"
        gateway = var.use_dhcp ? null : var.gateway
      }
    }

    # DNS configuration (only for static IP)
    dynamic "dns" {
      for_each = var.use_dhcp ? [] : [1]
      content {
        servers = var.dns_servers
      }
    }

    user_data_file_id = var.user_data_file_id
  }
}
