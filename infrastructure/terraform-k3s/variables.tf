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

# Node Configuration
variable "proxmox_nodes" {
  description = "Proxmox node configurations"
  type = map(object({
    name = string
    ip   = string
  }))
  default = {
    autobots = {
      name = "autobots"
      ip   = "192.168.50.176"
    }
    pve2 = {
      name = "pve2"
      ip   = "192.168.50.26"
    }
  }
}

# K3s Control Plane Configuration
variable "k3s_cp_nodes" {
  description = "K3s control plane node definitions"
  type = list(object({
    name        = string
    proxmox_node = string
    ip          = string
    user        = optional(string) # ansible_user override; falls back to var.vm_user
  }))
  default = [
    {
      name         = "k3s-cp-1"
      proxmox_node = "autobots"
      ip           = "10.10.10.11"
    },
    {
      name         = "k3s-cp-2"
      proxmox_node = "pve2"
      ip           = "10.10.10.12"
    }
  ]
}

# K3s Worker Configuration
variable "k3s_worker_nodes" {
  description = "K3s worker node definitions"
  type = list(object({
    name        = string
    proxmox_node = string
    ip          = string
    user        = optional(string) # ansible_user override; falls back to var.vm_user
  }))
  default = [
    {
      name         = "k3s-worker-1"
      proxmox_node = "pve2"
      ip           = "10.10.10.21"
    },
    {
      name         = "k3s-worker-2"
      proxmox_node = "pve2"
      ip           = "10.10.10.22"
    }
  ]
}

# VM Configuration
variable "vm_cp_vmid_start" {
  description = "Starting VM ID for K3s control plane nodes"
  type        = number
  default     = 300
}

variable "vm_worker_vmid_start" {
  description = "Starting VM ID for K3s worker nodes (fixed, independent of CP count)"
  type        = number
  default     = 310
}

variable "vm_cloud_image_url" {
  description = "URL of the cloud-init image"
  type        = string
  default     = "https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
}

variable "vm_cloud_image_datastore" {
  description = "Datastore for cloud image"
  type        = string
  default     = "local"
}

variable "vm_storage_pool" {
  description = "Storage pool for VM disks"
  type        = string
  default     = "local-lvm"
}

# Control Plane VM specs
variable "cp_cores" {
  description = "CPU cores for control plane nodes"
  type        = number
  default     = 2
}

variable "cp_memory" {
  description = "Memory (MB) for control plane nodes"
  type        = number
  default     = 4096
}

variable "cp_disk_size" {
  description = "Disk size (GB) for control plane nodes"
  type        = number
  default     = 50
}

# Worker VM specs
variable "worker_cores" {
  description = "CPU cores for worker nodes"
  type        = number
  default     = 4
}

variable "worker_memory" {
  description = "Memory (MB) for worker nodes"
  type        = number
  default     = 8192
}

variable "worker_disk_size" {
  description = "Disk size (GB) for worker nodes"
  type        = number
  default     = 100
}

# Network Configuration
variable "vm_bridge" {
  description = "Network bridge for VMs (vmbr1 = direct pve-pve2 link)"
  type        = string
  default     = "vmbr1"
}

variable "vm_gateway" {
  description = "Gateway IP for the lab network (VyOS on vmbr1)"
  type        = string
  default     = "10.10.10.1"
}

variable "vm_subnet_mask" {
  description = "Subnet mask in CIDR notation"
  type        = number
  default     = 24
}

variable "vm_dns_servers" {
  description = "DNS servers"
  type        = list(string)
  default     = ["1.1.1.1", "8.8.8.8"]
}

variable "vm_mtu" {
  description = "MTU for VM interfaces on the lab network (jumbo for 2.5Gb link)"
  type        = number
  default     = 9000
}

# SSH Configuration
variable "ssh_public_key" {
  description = "SSH public key for VM access"
  type        = string
}

variable "ssh_private_key_path" {
  description = "Path to SSH private key"
  type        = string
  default     = "~/.ssh/id_ed25519_homelab"
}

variable "vm_user" {
  description = "VM user for cloud-init"
  type        = string
  default     = "ubuntu"
}

variable "vm_password" {
  description = "VM password (optional)"
  type        = string
  sensitive   = true
  default     = ""
}

# K3s Configuration
variable "k3s_version" {
  description = "K3s version to install"
  type        = string
  default     = "v1.28.5+k3s1"
}

variable "k3s_token" {
  description = "K3s cluster token for node authentication"
  type        = string
  sensitive   = true
}

variable "k3s_cluster_init" {
  description = "Whether to initialize a new cluster (only first control plane)"
  type        = bool
  default     = false
}
