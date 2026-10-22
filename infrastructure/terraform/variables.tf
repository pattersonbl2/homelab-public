variable "proxmox_api_url" {
  description = "Proxmox API URL (should end with /, not /api2/json for BPG provider)"
  type        = string
  default     = "https://your-proxmox-server:8006/"
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
  description = "Skip TLS verification (for self-signed certificates)"
  type        = bool
  default     = true
}

variable "proxmox_debug" {
  description = "Enable debug logging"
  type        = bool
  default     = false
}

variable "proxmox_ssh_username" {
  description = "SSH username for Proxmox node (usually 'root')"
  type        = string
  default     = "root"
}

variable "proxmox_node" {
  description = "Proxmox node name"
  type        = string
  default     = "autobots"
}

variable "vm_count" {
  description = "Number of VMs to create"
  type        = number
  default     = 1
}

variable "vm_name_prefix" {
  description = "Prefix for VM names"
  type        = string
  default     = "homelab"
}

variable "vm_vmid_start" {
  description = "Starting VM ID"
  type        = number
  default     = 200
}

variable "vm_template" {
  description = "Proxmox template/VM to clone from (deprecated - using cloud image now)"
  type        = string
  default     = ""
}

variable "vm_cloud_image_url" {
  description = "URL of the cloud-init image to download"
  type        = string
  default     = "https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
}

variable "vm_cloud_image_filename" {
  description = "Filename for the downloaded cloud image"
  type        = string
  default     = "jammy-server-cloudimg-amd64.qcow2"
}

variable "vm_cloud_image_datastore" {
  description = "Datastore where cloud image will be downloaded"
  type        = string
  default     = "local"
}

variable "vm_memory" {
  description = "Memory in MB. For media stack (arr + Jellyfin + VPN) + AI: 16384 recommended."
  type        = number
  default     = 16384
}

variable "vm_cores" {
  description = "Number of CPU cores. 4 recommended for media stack."
  type        = number
  default     = 4
}

variable "vm_sockets" {
  description = "Number of CPU sockets"
  type        = number
  default     = 1
}
variable "vm_cpu_type" {
  description = "CPU type"
  type        = string
  default     = "host"
}

variable "vm_disk_type" {
  description = "Disk type (scsi, virtio, etc.)"
  type        = string
  default     = "scsi"
}

variable "vm_storage_pool" {
  description = "Storage pool name"
  type        = string
  default     = "local-lvm"
}

variable "vm_disk_size" {
  description = "Disk size in GB (as number, not string)"
  type        = number
  default     = 100
}

variable "vm_disk_format" {
  description = "Disk format (raw, qcow2, etc.)"
  type        = string
  default     = "raw"
}

variable "vm_bridge" {
  description = "Network bridge"
  type        = string
  default     = "vmbr0"
}

variable "vm_network_model" {
  description = "Network model (virtio, e1000, etc.)"
  type        = string
  default     = "virtio"
}

variable "vm_vlan_tag" {
  description = "VLAN tag (optional)"
  type        = number
  default     = 0
}

variable "vm_hostname" {
  description = "VM hostname prefix"
  type        = string
  default     = "homelab"
}

variable "ssh_public_key" {
  description = "SSH public key for VM access"
  type        = string
}

variable "ssh_private_key_path" {
  description = "Path to SSH private key for provisioning"
  type        = string
  default     = "~/.ssh/id_rsa"
}

variable "vm_user" {
  description = "VM user for cloud-init"
  type        = string
  default     = "ubuntu"
}

variable "vm_password" {
  description = "VM password (will be hashed by cloud-init)"
  type        = string
  sensitive   = true
}

variable "vm_ip_addresses" {
  description = "Optional: Manual IP addresses for VMs (if auto-detection fails). Leave empty to auto-detect."
  type        = list(string)
  default     = []
}

# ─── Tailscale LXC (remote access to homelab) ─────────────────────────────────

variable "tailscale_enabled" {
  description = "Create an LXC container running Tailscale as subnet router for remote access to homelab nodes."
  type        = bool
  default     = true
}

variable "tailscale_lxc_ip" {
  description = "Static IP for the Tailscale LXC container (must be on same subnet as homelab VMs)."
  type        = string
  default     = "192.168.50.5"
}

variable "tailscale_subnet_cidr" {
  description = "Subnet to advertise via Tailscale (your LAN so you can reach homelab VMs). e.g. 192.168.50.0/24"
  type        = string
  default     = "192.168.50.0/24"
}

variable "tailscale_gateway" {
  description = "Default gateway for the Tailscale LXC (usually your router)."
  type        = string
  default     = "192.168.50.1"
}

# ─── Database LXC (centralized PostgreSQL + Redis) ────────────────────────────

variable "db_lxc_enabled" {
  description = "Create an LXC container for centralized PostgreSQL 16 + Redis 7."
  type        = bool
  default     = true
}

variable "db_lxc_node" {
  description = "Proxmox node to place the database LXC on."
  type        = string
  default     = "pve2"
}

variable "pihole_lxc_ip" {
  description = "Static IP for pihole-lxc"
  type        = string
  default     = "192.168.50.20"
}

variable "jellyfin_lxc_ip" {
  description = "Static IP for jellyfin-lxc"
  type        = string
  default     = "192.168.50.21"
}

variable "pihole_lxc2_ip" {
  description = "Static IP for secondary Pi-hole LXC on pve2"
  type        = string
  default     = "192.168.50.22"
}

variable "wheeljack_lxc_ip" {
  description = "Static IP for the Wheeljack LXC container (Hermes AI agent)"
  type        = string
  default     = "192.168.50.25"
}