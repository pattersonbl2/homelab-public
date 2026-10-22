# Local values for VM IP addresses with fallbacks
locals {
  vm_ips = {
    for idx in range(var.vm_count) : idx => coalesce(
      # Manual IP override
      try(var.vm_ip_addresses[idx], null),
      # Try to get IPs from QEMU agent via module output (with null checks)
      try(length(module.docker_vm[idx].ipv4_addresses) > 1 ? module.docker_vm[idx].ipv4_addresses[1][0] : null, null),
      try(length(module.docker_vm[idx].ipv4_addresses) > 0 ? module.docker_vm[idx].ipv4_addresses[0][0] : null, null),
      # Fallback to hostname
      "${var.vm_name_prefix}-${idx + 1}.local"
    )
  }

  # LocalAI GPU VM IP (same fallback logic as homelab VMs)
  localai_gpu_ip = coalesce(
    try(length(module.localai_gpu_vm.ipv4_addresses) > 1 ? module.localai_gpu_vm.ipv4_addresses[1][0] : null, null),
    try(length(module.localai_gpu_vm.ipv4_addresses) > 0 ? module.localai_gpu_vm.ipv4_addresses[0][0] : null, null),
    "localai-gpu.local"
  )

  # Tailscale LXC IP (static, set in variables)
  tailscale_ip = var.tailscale_enabled ? var.tailscale_lxc_ip : null

  # Proxmox host for SSH (from API URL, for LXC TUN config)
  proxmox_host = var.tailscale_enabled ? split(":", replace(replace(var.proxmox_api_url, "https://", ""), "http://", ""))[0] : ""
}
