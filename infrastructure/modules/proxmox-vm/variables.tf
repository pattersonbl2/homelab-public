# Proxmox VM Module - Variables
# Reusable module for creating VMs on Proxmox with the BPG provider

variable "vm_name" {
  description = "Name of the VM"
  type        = string
}

variable "proxmox_node" {
  description = "Proxmox node to create the VM on"
  type        = string
}

variable "vm_id" {
  description = "VM ID in Proxmox"
  type        = number
}

variable "cores" {
  description = "Number of CPU cores"
  type        = number
  default     = 2
}

variable "memory" {
  description = "Memory in MB"
  type        = number
  default     = 4096
}

variable "disk_size" {
  description = "Disk size in GB"
  type        = number
  default     = 50
}

variable "disk_interface" {
  description = "Disk interface type (scsi, virtio, etc.)"
  type        = string
  default     = "scsi"
}

variable "bridge" {
  description = "Network bridge"
  type        = string
  default     = "vmbr0"
}

variable "network_model" {
  description = "Network model (virtio, e1000, etc.)"
  type        = string
  default     = "virtio"
}

variable "use_dhcp" {
  description = "Use DHCP for IP configuration"
  type        = bool
  default     = true
}

variable "static_ip" {
  description = "Static IP address (required if use_dhcp is false)"
  type        = string
  default     = ""
}

variable "subnet_mask" {
  description = "Subnet mask in CIDR notation (required if use_dhcp is false)"
  type        = number
  default     = 24
}

variable "gateway" {
  description = "Gateway IP (required if use_dhcp is false)"
  type        = string
  default     = ""
}

variable "dns_servers" {
  description = "DNS servers (optional, used with static IP)"
  type        = list(string)
  default     = ["1.1.1.1", "8.8.8.8"]
}

variable "user_data_file_id" {
  description = "Cloud-init user data file ID"
  type        = string
}

variable "cloud_image_id" {
  description = "Cloud image file ID for VM disk"
  type        = string
}

variable "storage_pool" {
  description = "Storage pool for VM disk"
  type        = string
  default     = "local-lvm"
}

variable "tags" {
  description = "Tags to apply to the VM"
  type        = list(string)
  default     = []
}

variable "description" {
  description = "VM description"
  type        = string
  default     = ""
}

variable "cpu_type" {
  description = "CPU type"
  type        = string
  default     = "host"
}

variable "stop_on_destroy" {
  description = "Stop VM on destroy"
  type        = bool
  default     = true
}

variable "agent_enabled" {
  description = "Enable QEMU guest agent"
  type        = bool
  default     = true
}

variable "machine_type" {
  description = "Machine type (i440fx or q35). q35 required for PCIe passthrough."
  type        = string
  default     = "i440fx"
}

variable "hostpci_devices" {
  description = "PCIe devices to pass through. Use 'mapping' for Proxmox resource mappings (required for API tokens), or 'id' for raw PCI addresses."
  type = list(object({
    id      = optional(string)
    mapping = optional(string)
    pcie    = optional(bool, true)
    rombar  = optional(bool, true)
    x_vga   = optional(bool, false)
  }))
  default = []
}
