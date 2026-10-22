output "vyos_router_info" {
  description = "VyOS router VM information"
  value = {
    vm_id       = proxmox_virtual_environment_vm.vyos_router.vm_id
    name        = proxmox_virtual_environment_vm.vyos_router.name
    node        = proxmox_virtual_environment_vm.vyos_router.node_name
    wan_ip      = local.vyos_wan_ip
    lan_ip      = local.vyos_lan_ip
    wan_bridge  = local.vyos_wan_bridge
    lan_bridge  = local.vyos_lan_bridge
    description = "After VM boots, install VyOS and configure via console or Ansible"
  }
}
