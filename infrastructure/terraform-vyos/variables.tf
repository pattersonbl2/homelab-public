# Proxmox API Configuration
variable "proxmox_api_url" {
  description = "Proxmox API URL"
  type        = string
}

variable "proxmox_api_token_id" {
  description = "Proxmox API Token ID"
  type        = string
  sensitive   = true
}

variable "proxmox_api_token_secret" {
  description = "Proxmox API Token Secret"
  type        = string
  sensitive   = true
}

variable "proxmox_tls_insecure" {
  description = "Skip TLS verification"
  type        = bool
  default     = true
}

variable "proxmox_ssh_username" {
  description = "SSH username for Proxmox nodes"
  type        = string
  default     = "root"
}

# Storage Configuration
variable "vm_cloud_image_datastore" {
  description = "Datastore for ISO files"
  type        = string
  default     = "local"
}

variable "vm_storage_pool" {
  description = "Storage pool for VM disks"
  type        = string
  default     = "local-lvm"
}

# VyOS VM Configuration
variable "vyos_vm_id" {
  description = "VM ID for VyOS router"
  type        = number
  default     = 200
}

variable "vyos_vm_name" {
  description = "Name of the VyOS router VM"
  type        = string
  default     = "vyos-gw"
}

variable "vyos_node" {
  description = "Proxmox node to deploy VyOS on"
  type        = string
  default     = "pve"
}

variable "vyos_iso_filename" {
  description = "Filename of the VyOS ISO in the datastore"
  type        = string
  default     = "vyos-2026.01.18-0024-rolling-generic-amd64.iso"
}

# VyOS VM Specs
variable "vyos_cores" {
  description = "CPU cores for VyOS router"
  type        = number
  default     = 2
}

variable "vyos_cpu_type" {
  description = "CPU type for VyOS router"
  type        = string
  default     = "host"
}

variable "vyos_memory" {
  description = "Memory (MB) for VyOS router"
  type        = number
  default     = 2048
}

variable "vyos_disk_size" {
  description = "Disk size (GB) for VyOS router"
  type        = number
  default     = 10
}

variable "vyos_network_model" {
  description = "Network adapter model for VyOS"
  type        = string
  default     = "virtio"
}

# Network Configuration
variable "vyos_wan_bridge" {
  description = "Network bridge for WAN interface"
  type        = string
  default     = "vmbr0"
}

variable "vyos_lan_bridge" {
  description = "Network bridge for LAN interface (direct link between pve nodes)"
  type        = string
  default     = "vmbr1"
}

variable "vyos_wan_ip" {
  description = "WAN IP address"
  type        = string
  default     = "192.168.50.18/24"
}

variable "vyos_lan_ip" {
  description = "LAN IP address"
  type        = string
  default     = "10.10.10.1"
}
