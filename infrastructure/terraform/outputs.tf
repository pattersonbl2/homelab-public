output "vm_names" {
  description = "Names of created VMs"
  value       = [for vm in module.docker_vm : vm.vm_name]
}

output "vm_ids" {
  description = "VM IDs"
  value       = [for vm in module.docker_vm : vm.vm_id]
}

output "vm_hostnames" {
  description = "Hostnames of created VMs (DHCP will assign IPs)"
  value       = [for vm in module.docker_vm : vm.vm_name]
}

output "vm_ip_addresses" {
  description = "IP addresses of created VMs (with fallback to hostname if IP not available)"
  value = [
    for idx in range(var.vm_count) : local.vm_ips[idx]
  ]
}

output "vm_ip_addresses_map" {
  description = "Map of VM names to IP addresses"
  value = {
    for idx in range(var.vm_count) : module.docker_vm[idx].vm_name => local.vm_ips[idx]
  }
}

output "ssh_connection_strings" {
  description = "SSH connection strings (using IP addresses or hostnames)"
  value = [
    for idx in range(var.vm_count) : "ssh ${var.vm_user}@${local.vm_ips[idx]}"
  ]
}

output "ansible_inventory_content" {
  description = "Ansible inventory file content (can be saved to a file)"
  value = templatefile("${path.module}/templates/ansible-inventory.tpl", {
    ssh_private_key_path = var.ssh_private_key_path
    vms = [
      for idx in range(var.vm_count) : {
        name                 = module.docker_vm[idx].vm_name
        ip                   = local.vm_ips[idx]
        user                 = var.vm_user
        ssh_private_key_path = var.ssh_private_key_path
      }
    ]
    localai_gpu_vms = [
      {
        name                 = module.localai_gpu_vm.vm_name
        ip                   = local.localai_gpu_ip
        user                 = var.vm_user
        ssh_private_key_path = var.ssh_private_key_path
      }
    ]
    tailscale_hosts = var.tailscale_enabled ? [
      {
        name                 = "tailscale-1"
        ip                   = local.tailscale_ip
        user                 = "root"
        ssh_private_key_path = var.ssh_private_key_path
      }
    ] : []
  })
  sensitive = true
}

output "vm_user" {
  description = "VM user for Ansible"
  value       = var.vm_user
}

# ─── LocalAI GPU Outputs ───────────────────────────────────────────────────────

output "localai_gpu_vm_ip" {
  description = "LocalAI GPU VM IP address"
  value       = local.localai_gpu_ip
}

output "localai_gpu_vm_name" {
  description = "LocalAI GPU VM name"
  value       = module.localai_gpu_vm.vm_name
}

output "localai_gpu_ssh_connection" {
  description = "SSH connection string for LocalAI GPU VM"
  value       = "ssh ${var.vm_user}@${local.localai_gpu_ip}"
}

output "localai_gpu_ui_url" {
  description = "LocalAI GPU Open WebUI URL"
  value       = "http://${local.localai_gpu_ip}:18789"
}

# ─── Tailscale LXC Outputs ────────────────────────────────────────────────────

output "tailscale_lxc_ip" {
  description = "Tailscale LXC container IP (subnet router)"
  value       = local.tailscale_ip
}

output "tailscale_configure_instructions" {
  description = "Instructions to configure Tailscale after apply"
  value       = var.tailscale_enabled ? "Run: cd ansible && ansible-playbook -i inventory.ini tailscale.yml -e tailscale_auth_key=tskey-auth-XXX -e tailscale_advertise_routes=${var.tailscale_subnet_cidr}" : "Tailscale LXC is disabled."
}

# ─── Database LXC Outputs ───────────────────────────────────────────────────

output "db_lxc_id" {
  description = "Database LXC container ID"
  value       = var.db_lxc_enabled ? proxmox_virtual_environment_container.db[0].id : null
}
