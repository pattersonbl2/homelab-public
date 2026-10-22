terraform {
  required_version = ">= 1.0"

  backend "s3" {}

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.90"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
  }
}

provider "proxmox" {
  endpoint  = var.proxmox_api_url
  api_token = "${var.proxmox_api_token_id}=${var.proxmox_api_token_secret}"
  insecure  = var.proxmox_tls_insecure

  ssh {
    agent    = true
    username = var.proxmox_ssh_username
  }
}

# Cloud-init configuration for Docker VMs
resource "proxmox_virtual_environment_file" "docker_cloud_config" {
  count = var.vm_count

  content_type = "snippets"
  datastore_id = var.vm_cloud_image_datastore
  node_name    = var.proxmox_node

  source_raw {
    data = templatefile("${path.module}/templates/cloud-init-docker.tpl", {
      hostname       = "${var.vm_hostname}-${count.index + 1}"
      username       = var.vm_user
      ssh_public_key = trimspace(var.ssh_public_key)
    })
    file_name = "docker-cloud-config-${count.index + 1}.yaml"
  }
}

# Download Cloud-Init Image (Ubuntu 22.04)
resource "proxmox_virtual_environment_download_file" "ubuntu_cloud_image" {
  content_type = "iso"
  datastore_id = var.vm_cloud_image_datastore
  node_name    = var.proxmox_node

  url       = var.vm_cloud_image_url
  file_name = "jammy-server-cloudimg-amd64.img"

  overwrite = false

  lifecycle {
    ignore_changes = [
      url,
      file_name,
    ]
  }
}

# Docker VM using the proxmox-vm module
module "docker_vm" {
  source = "../modules/proxmox-vm"
  count  = var.vm_count

  vm_name           = "${var.vm_name_prefix}-${count.index + 1}"
  proxmox_node      = var.proxmox_node
  vm_id             = var.vm_vmid_start + count.index
  cores             = var.vm_cores
  memory            = var.vm_memory
  disk_size         = var.vm_disk_size
  disk_interface    = var.vm_disk_type
  bridge            = var.vm_bridge
  network_model     = var.vm_network_model
  cpu_type          = var.vm_cpu_type
  storage_pool      = var.vm_storage_pool
  use_dhcp          = true
  user_data_file_id = proxmox_virtual_environment_file.docker_cloud_config[count.index].id
  cloud_image_id    = proxmox_virtual_environment_download_file.ubuntu_cloud_image.id
  tags              = ["docker", "homelab"]
  description       = "Homelab VM with Docker Compose - ${var.vm_name_prefix}-${count.index + 1}"

  # Intel Alder Lake iGPU passthrough for Jellyfin QuickSync transcoding
  machine_type = "q35"
  hostpci_devices = [
    { mapping = "igpu-jellyfin", pcie = true, rombar = false }
  ]
}

# Generate Ansible inventory file automatically from VM IPs
resource "local_file" "ansible_inventory" {
  count    = var.vm_count > 0 ? 1 : 0
  filename = "${path.module}/../ansible/inventory.ini"
  content = templatefile("${path.module}/templates/ansible-inventory.tpl", {
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

  depends_on = [
    module.docker_vm,
    module.localai_gpu_vm
  ]
}

# Ansible provisioner for Docker Compose deployment
resource "null_resource" "docker_compose_ansible" {
  count = var.vm_count

  triggers = {
    vm_id               = module.docker_vm[count.index].id
    vm_ip               = local.vm_ips[count.index]
    playbook_hash       = filemd5("${path.module}/../ansible/playbook.yml")
    deploy_stacks_hash  = filemd5("${path.module}/../ansible/deploy-stacks.yml")
    inventory_hash      = local_file.ansible_inventory[0].content_sha256
    docker_compose_hash = filemd5("${path.module}/../../stacks/core/docker-compose.yml")
    traefik_config_hash = filemd5("${path.module}/../../stacks/core/traefik.yml")
  }

  depends_on = [
    module.docker_vm,
    local_file.ansible_inventory
  ]

  provisioner "local-exec" {
    command     = <<-EOT
      REPO_ROOT="${abspath(path.module)}/../.."
      ANSIBLE_DIR="$REPO_ROOT/infrastructure/ansible"
      if [ -f "$ANSIBLE_DIR/inventory.ini" ]; then
        INVENTORY_FILE="$ANSIBLE_DIR/inventory.ini"
        ANSIBLE_LIMIT="${module.docker_vm[count.index].vm_name}"
        ANSIBLE_ARGS="--limit $ANSIBLE_LIMIT"
      else
        INVENTORY_FILE="$ANSIBLE_DIR/inventory-${count.index}.ini"
        ANSIBLE_ARGS=""
        cat > $INVENTORY_FILE <<INVEOF
[homelab_vms]
${module.docker_vm[count.index].vm_name} ansible_host=${local.vm_ips[count.index]} ansible_user=${var.vm_user} ansible_ssh_private_key_file=${var.ssh_private_key_path} ansible_ssh_common_args='-o StrictHostKeyChecking=accept-new'
INVEOF
      fi
      cd "$ANSIBLE_DIR" && ansible-playbook -i "$INVENTORY_FILE" playbook.yml $ANSIBLE_ARGS
      [ "$INVENTORY_FILE" != "$ANSIBLE_DIR/inventory.ini" ] && rm -f "$INVENTORY_FILE" || true
    EOT
    working_dir = path.module
    environment = {
      ANSIBLE_HOST_KEY_CHECKING = "False"
    }
  }

  provisioner "local-exec" {
    when    = destroy
    command = "rm -f ${path.module}/../ansible/inventory-${count.index}.ini"
  }
}

# ─── LocalAI GPU Dedicated VM ──────────────────────────────────────────────────

# Cloud-init for LocalAI GPU VM (security-hardened: UFW, fail2ban, SSH hardening)
resource "proxmox_virtual_environment_file" "localai_gpu_cloud_config" {
  content_type = "snippets"
  datastore_id = var.vm_cloud_image_datastore
  node_name    = var.proxmox_node

  source_raw {
    data = templatefile("${path.module}/templates/cloud-init-localai-gpu.tpl", {
      hostname       = "localai-gpu"
      username       = var.vm_user
      ssh_public_key = trimspace(var.ssh_public_key)
    })
    file_name = "localai-gpu-cloud-config.yaml"
  }
}

# LocalAI GPU VM: 6 cores, 8GB RAM, 200GB disk — isolated from homelab-1
# GPU handles LLM inference now, reduced from 16GB
module "localai_gpu_vm" {
  source = "../modules/proxmox-vm"

  vm_name           = "localai-gpu"
  proxmox_node      = var.proxmox_node
  vm_id             = 115
  cores             = 6
  memory            = 8192
  disk_size         = 200
  disk_interface    = var.vm_disk_type
  bridge            = var.vm_bridge
  network_model     = var.vm_network_model
  cpu_type          = var.vm_cpu_type
  storage_pool      = var.vm_storage_pool
  use_dhcp          = true
  user_data_file_id = proxmox_virtual_environment_file.localai_gpu_cloud_config.id
  cloud_image_id    = proxmox_virtual_environment_download_file.ubuntu_cloud_image.id
  tags              = ["docker", "localai-gpu"]
  description       = "LocalAI GPU VM - RTX 3060 for AI/LLM inference (Ollama + Open WebUI)"

  # NVIDIA RTX 3060 12GB passthrough for AI/LLM workloads (Ollama + Open WebUI)
  machine_type = "q35"
  hostpci_devices = [
    { mapping = "rtx3060-openclaw", pcie = true }
  ]
}

# Ansible provisioner for dedicated AI tools stack deployment
resource "null_resource" "localai_gpu_ansible" {
  triggers = {
    vm_id              = module.localai_gpu_vm.id
    vm_ip              = local.localai_gpu_ip
    deploy_stacks_hash = filemd5("${path.module}/../ansible/deploy-stacks.yml")
    compose_hash       = filemd5("${path.module}/../../stacks/ai-tools/docker-compose.yml")
  }

  depends_on = [
    module.localai_gpu_vm,
  ]

  provisioner "local-exec" {
    command     = <<-EOT
      REPO_ROOT="${abspath(path.module)}/../.."
      ANSIBLE_DIR="$REPO_ROOT/infrastructure/ansible"
      cd "$ANSIBLE_DIR" && ansible-playbook -i inventory.ini deploy-stacks.yml \
        --limit localai-gpu \
        -e '{"stacks_to_deploy": ["ai-tools"]}'
    EOT
    working_dir = path.module
    environment = {
      ANSIBLE_HOST_KEY_CHECKING = "False"
    }
  }
}

# ─── Tailscale LXC (subnet router for remote access) ──────────────────────────

# Use existing LXC template on Proxmox (ensure it exists: pveam download local ubuntu-22.04-standard_22.04-1_amd64.tar.zst)
resource "proxmox_virtual_environment_container" "tailscale" {
  count = var.tailscale_enabled ? 1 : 0

  node_name    = var.proxmox_node
  vm_id        = 116
  description  = "Tailscale subnet router - remote access to homelab"
  tags         = ["tailscale", "homelab"]
  # Privileged so tailscaled can use /dev/net/tun for VPN
  unprivileged = false

  initialization {
    hostname = "tailscale-1"
    ip_config {
      ipv4 {
        address = "${var.tailscale_lxc_ip}/24"
        gateway = var.tailscale_gateway
      }
    }
    user_account {
      keys     = [trimspace(var.ssh_public_key)]
      password = var.vm_password != "" ? var.vm_password : "changeme-tailscale"
    }
  }

  network_interface {
    name   = "eth0"
    bridge = var.vm_bridge
  }

  operating_system {
    # Direct volume ID: template must exist on Proxmox (pveam download local ubuntu-22.04-standard_22.04-1_amd64.tar.zst)
    template_file_id = "local:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.zst"
    type             = "ubuntu"
  }

  disk {
    datastore_id = var.vm_storage_pool
    size         = 4
  }

  memory {
    dedicated = 512
  }

  cpu {
    cores = 1
  }

  start_on_boot = true
}

# Enable /dev/net/tun in Tailscale LXC (required for tailscaled)
resource "null_resource" "tailscale_lxc_tun" {
  count = var.tailscale_enabled ? 1 : 0

  triggers = {
    container_id = proxmox_virtual_environment_container.tailscale[0].id
  }

  provisioner "local-exec" {
    command = join("\n", [
      "ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 ${var.proxmox_ssh_username}@${local.proxmox_host} \"CONF=/etc/pve/lxc/${proxmox_virtual_environment_container.tailscale[0].vm_id}.conf; grep -q 'lxc.cgroup2.devices.allow.*10:200' \\$CONF || echo 'lxc.cgroup2.devices.allow: c 10:200 rwm' >> \\$CONF\"",
      "ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 ${var.proxmox_ssh_username}@${local.proxmox_host} \"CONF=/etc/pve/lxc/${proxmox_virtual_environment_container.tailscale[0].vm_id}.conf; grep -q 'lxc.mount.entry.*dev/net/tun' \\$CONF || echo 'lxc.mount.entry: /dev/net/tun dev/net/tun none bind,create=file 0 0' >> \\$CONF\"",
      "ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 ${var.proxmox_ssh_username}@${local.proxmox_host} \"CONF=/etc/pve/lxc/${proxmox_virtual_environment_container.tailscale[0].vm_id}.conf; grep -q 'lxc.sysctl.net.ipv4.ip_forward' \\$CONF || echo 'lxc.sysctl.net.ipv4.ip_forward = 1' >> \\$CONF\"",
      "ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 ${var.proxmox_ssh_username}@${local.proxmox_host} \"pct reboot ${proxmox_virtual_environment_container.tailscale[0].vm_id}\"",
    ])
  }

  depends_on = [proxmox_virtual_environment_container.tailscale]
}

# ─── Database LXC (centralized PostgreSQL + Redis) ─────────────────────────────

resource "proxmox_virtual_environment_container" "db" {
  count = var.db_lxc_enabled ? 1 : 0

  node_name    = var.db_lxc_node
  vm_id        = 117
  description  = "Centralized PostgreSQL 16 + Redis 7 for all Docker stacks"
  tags         = ["database", "homelab"]
  unprivileged = true

  initialization {
    hostname = "db-1"
    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }
    user_account {
      keys     = [trimspace(var.ssh_public_key)]
      password = var.vm_password != "" ? var.vm_password : "changeme-db"
    }
  }

  network_interface {
    name   = "eth0"
    bridge = var.vm_bridge
  }

  operating_system {
    template_file_id = "local:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.zst"
    type             = "ubuntu"
  }

  disk {
    datastore_id = var.vm_storage_pool
    size         = 20
  }

  memory {
    dedicated = 2048
  }

  cpu {
    cores = 2
  }

  mount_point {
    volume = "/mnt/backup/db"
    path   = "/mnt/backup/db"
  }

  features {
    nesting = true
    mount   = ["nfs"]
  }

  start_on_boot = true
}

# ─── Pihole LXC 2 (VMID 122) — Secondary DNS on pve2 ─────────────────────────
resource "proxmox_virtual_environment_container" "pihole_lxc2" {
  node_name    = var.db_lxc_node
  vm_id        = 122
  description  = "Secondary Pi-hole DNS — replica of pihole-lxc (192.168.50.20)"
  tags         = ["pihole", "dns", "homelab"]
  unprivileged = true

  initialization {
    hostname = "pihole-lxc-2"
    ip_config {
      ipv4 {
        address = "${var.pihole_lxc2_ip}/24"
        gateway = var.tailscale_gateway
      }
    }
    user_account {
      keys     = [trimspace(var.ssh_public_key)]
      password = var.vm_password != "" ? var.vm_password : "changeme-pihole2"
    }
  }

  network_interface {
    name   = "eth0"
    bridge = var.vm_bridge
  }

  operating_system {
    template_file_id = "local:vztmpl/debian-12-standard_12.12-1_amd64.tar.zst"
    type             = "debian"
  }

  disk {
    datastore_id = var.vm_storage_pool
    size         = 4
  }

  memory {
    dedicated = 512
  }

  cpu {
    cores = 1
  }

  start_on_boot = true
}

# ─── Wheeljack LXC (VMID 123) — Hermes AI Agent ──────────────────────────────
resource "proxmox_virtual_environment_container" "wheeljack" {
  node_name    = var.proxmox_node
  vm_id        = 123
  description  = "Hermes AI agent (Nous Research) — autonomous assistant via Telegram"
  tags         = ["hermes", "ai", "homelab"]
  unprivileged = true

  initialization {
    hostname = "wheeljack"
    ip_config {
      ipv4 {
        address = "${var.wheeljack_lxc_ip}/24"
        gateway = var.tailscale_gateway
      }
    }
    user_account {
      keys     = [trimspace(var.ssh_public_key)]
      password = var.vm_password != "" ? var.vm_password : "changeme-wheeljack"
    }
  }

  network_interface {
    name   = "eth0"
    bridge = var.vm_bridge
  }

  operating_system {
    template_file_id = "local:vztmpl/debian-12-standard_12.12-1_amd64.tar.zst"
    type             = "debian"
  }

  disk {
    datastore_id = var.vm_storage_pool
    size         = 16
  }

  memory {
    dedicated = 2048
  }

  cpu {
    cores = 2
  }

  start_on_boot = true
}

# ─── Pihole LXC (VMID 121) and Jellyfin LXC (VMID 119) ───────────────────────
# These LXCs are managed outside Terraform due to manual GPU passthrough and
# NFS bind-mount configurations that require root@pam access (API token 403).
# Created via Proxmox UI + Ansible. See ansible/install-pihole-lxc.yml and
# ansible/install-jellyfin-lxc.yml for provisioning details.
