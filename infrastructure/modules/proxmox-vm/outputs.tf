# Proxmox VM Module - Outputs

output "vm_id" {
  description = "The VM ID in Proxmox"
  value       = proxmox_virtual_environment_vm.vm.vm_id
}

output "vm_name" {
  description = "The VM name"
  value       = proxmox_virtual_environment_vm.vm.name
}

output "ipv4_addresses" {
  description = "IPv4 addresses detected by QEMU agent"
  value       = proxmox_virtual_environment_vm.vm.ipv4_addresses
}

output "id" {
  description = "The full resource ID"
  value       = proxmox_virtual_environment_vm.vm.id
}

output "node_name" {
  description = "The Proxmox node the VM is on"
  value       = proxmox_virtual_environment_vm.vm.node_name
}
