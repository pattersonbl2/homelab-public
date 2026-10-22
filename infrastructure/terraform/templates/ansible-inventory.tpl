[homelab_vms]
%{ for vm in vms ~}
${vm.name} ansible_host=${vm.ip} ansible_user=${vm.user} ansible_ssh_private_key_file=${vm.ssh_private_key_path} ansible_ssh_common_args='-o StrictHostKeyChecking=accept-new'
%{ endfor ~}
%{ for vm in localai_gpu_vms ~}
${vm.name} ansible_host=${vm.ip} ansible_user=${vm.user} ansible_ssh_private_key_file=${vm.ssh_private_key_path} ansible_ssh_common_args='-o StrictHostKeyChecking=accept-new'
%{ endfor ~}

%{ if length(tailscale_hosts) > 0 ~}
[tailscale]
%{ for h in tailscale_hosts ~}
${h.name} ansible_host=${h.ip} ansible_user=${h.user} ansible_ssh_private_key_file=${h.ssh_private_key_path} ansible_ssh_common_args='-o StrictHostKeyChecking=accept-new'
%{ endfor ~}
%{ endif ~}

[lxcs]
pihole-lxc   ansible_host=192.168.50.20 ansible_user=root ansible_ssh_private_key_file=${ssh_private_key_path} ansible_ssh_common_args='-o StrictHostKeyChecking=accept-new'
pihole-lxc-2 ansible_host=192.168.50.22 ansible_user=root ansible_ssh_private_key_file=${ssh_private_key_path} ansible_ssh_common_args='-o StrictHostKeyChecking=accept-new'
jellyfin-lxc ansible_host=192.168.50.21 ansible_user=root ansible_ssh_private_key_file=${ssh_private_key_path} ansible_ssh_common_args='-o StrictHostKeyChecking=accept-new'
wheeljack    ansible_host=192.168.50.25 ansible_user=root ansible_ssh_private_key_file=${ssh_private_key_path} ansible_ssh_common_args='-o StrictHostKeyChecking=accept-new'

[db]
db-1 ansible_host=192.168.50.15 ansible_user=root ansible_ssh_private_key_file=${ssh_private_key_path} ansible_ssh_common_args='-o StrictHostKeyChecking=accept-new'
