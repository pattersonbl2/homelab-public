output "k3s_control_plane_ips" {
  description = "K3s control plane node IPs"
  value = {
    for name, node in local.cp_nodes_indexed : name => node.ip
  }
}

output "k3s_worker_ips" {
  description = "K3s worker node IPs"
  value = {
    for name, node in local.worker_nodes_indexed : name => node.ip
  }
}

output "k3s_all_nodes" {
  description = "All K3s nodes with their details"
  value = {
    control_plane = [
      for name, node in local.cp_nodes_indexed : {
        name         = node.name
        ip           = node.ip
        proxmox_node = node.proxmox_node
        vmid         = node.vmid
      }
    ]
    workers = [
      for name, node in local.worker_nodes_indexed : {
        name         = node.name
        ip           = node.ip
        proxmox_node = node.proxmox_node
        vmid         = node.vmid
      }
    ]
  }
}

output "ssh_command_cp1" {
  description = "SSH command for first control plane node"
  value       = "ssh ${var.vm_user}@${var.k3s_cp_nodes[0].ip}"
}

output "ansible_inventory" {
  description = "Ansible inventory content for K3s nodes"
  value = <<-EOT
[k3s_cp]
%{ for node in var.k3s_cp_nodes ~}
${node.name} ansible_host=${node.ip} ansible_user=${var.vm_user} ansible_ssh_private_key_file=${var.ssh_private_key_path} ansible_ssh_common_args='-o StrictHostKeyChecking=accept-new'
%{ endfor ~}

[k3s_worker]
%{ for node in var.k3s_worker_nodes ~}
${node.name} ansible_host=${node.ip} ansible_user=${var.vm_user} ansible_ssh_private_key_file=${var.ssh_private_key_path} ansible_ssh_common_args='-o StrictHostKeyChecking=accept-new'
%{ endfor ~}

[k3s:children]
k3s_cp
k3s_worker
  EOT
  sensitive = false
}
