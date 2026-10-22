variable "truenas_host" {
  description = "TrueNAS SCALE host URL (e.g. https://192.168.50.10 or https://truenas.local)"
  type        = string
}

variable "truenas_api_token" {
  description = "API token from TrueNAS System > API Keys"
  type        = string
  sensitive   = true
}

variable "datasets" {
  description = "List of dataset paths to create (pool/name or pool/parent/child)"
  type        = list(string)
  default     = []
}

variable "backup_docker_client_ips" {
  description = "IPs allowed to access the docker backup NFS export"
  type        = list(string)
  default     = []
}

variable "backup_db_client_ips" {
  description = "IPs allowed to access the db backup NFS export (db-1 LXC + its Proxmox host)"
  type        = list(string)
  default     = []
}

variable "backup_k3s_client_network" {
  description = "K3s node subnet for NFS backup export (CIDR)"
  type        = string
  default     = "10.10.10.0/24"
}

