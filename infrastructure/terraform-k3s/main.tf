terraform {
  required_version = ">= 1.0"

  backend "s3" {}

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.90"
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

locals {
  # Combine all nodes for cloud image download
  all_proxmox_nodes = distinct(concat(
    [for n in var.k3s_cp_nodes : n.proxmox_node],
    [for n in var.k3s_worker_nodes : n.proxmox_node]
  ))

  # Create indexed maps for VM IDs
  cp_nodes_indexed = { for idx, node in var.k3s_cp_nodes : node.name => {
    index        = idx
    name         = node.name
    proxmox_node = node.proxmox_node
    ip           = node.ip
    vmid         = var.vm_cp_vmid_start + idx
  }}

  worker_nodes_indexed = { for idx, node in var.k3s_worker_nodes : node.name => {
    index        = idx
    name         = node.name
    proxmox_node = node.proxmox_node
    ip           = node.ip
    vmid         = var.vm_worker_vmid_start + idx
  }}
}

# Download cloud image to each Proxmox node
resource "proxmox_virtual_environment_download_file" "ubuntu_cloud_image" {
  for_each = toset(local.all_proxmox_nodes)

  content_type = "iso"
  datastore_id = var.vm_cloud_image_datastore
  node_name    = each.value
  url          = var.vm_cloud_image_url
  file_name    = "ubuntu-jammy-k3s.img"

  lifecycle {
    ignore_changes = [url, file_name]
  }
}

# Cloud-init config for control plane nodes
resource "proxmox_virtual_environment_file" "k3s_cp_cloud_config" {
  for_each = local.cp_nodes_indexed

  content_type = "snippets"
  datastore_id = var.vm_cloud_image_datastore
  node_name    = each.value.proxmox_node

  source_raw {
    data = <<-EOF
#cloud-config
hostname: ${each.value.name}
timezone: America/Toronto

users:
  - default
  - name: ${var.vm_user}
    groups: sudo
    shell: /bin/bash
    lock_passwd: false
    ssh_authorized_keys:
      - ${trimspace(var.ssh_public_key)}
    sudo: ALL=(ALL) NOPASSWD:ALL

chpasswd:
  expire: false
  users:
    - name: ${var.vm_user}
      password: ${var.vm_password}
      type: text

# Disable automatic package updates to prevent apt locks
# We'll handle package installation manually with proper lock handling
package_update: false
package_upgrade: false

write_files:
  - path: /usr/local/sbin/wait-for-apt.sh
    permissions: '0755'
    content: |
      #!/bin/bash
      # Wait for apt lock to be released
      set -e
      max_attempts=60
      attempt=0
      while [ $attempt -lt $max_attempts ]; do
        if ! lsof /var/lib/dpkg/lock-frontend /var/lib/apt/lists/lock /var/cache/apt/archives/lock >/dev/null 2>&1; then
          # Try to acquire lock
          if sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; then
            sleep 2
            attempt=$((attempt + 1))
            continue
          fi
          break
        fi
        sleep 2
        attempt=$((attempt + 1))
      done
      if [ $attempt -eq $max_attempts ]; then
        echo "Timeout waiting for apt lock" >&2
        exit 1
      fi
  - path: /usr/local/sbin/safe-apt-install.sh
    permissions: '0755'
    content: |
      #!/bin/bash
      # Safely install packages with apt lock handling
      set -e
      /usr/local/sbin/wait-for-apt.sh
      export DEBIAN_FRONTEND=noninteractive
      export APT_LISTCHANGES_FRONTEND=none
      apt-get update -o Acquire::Retries=3 -o Acquire::http::Timeout=30
      apt-get install -y -o Dpkg::Options::="--force-confold" -o Dpkg::Options::="--force-confdef" "$@"
  - path: /etc/sysctl.d/99-kubernetes.conf
    content: |
      net.bridge.bridge-nf-call-iptables = 1
      net.bridge.bridge-nf-call-ip6tables = 1
      net.ipv4.ip_forward = 1
      net.ipv4.tcp_mtu_probing = 1
  - path: /etc/netplan/99-k3s-mtu.yaml
    content: |
      network:
        version: 2
        ethernets:
          all:
            match:
              name: "e*"
            dhcp4: false
            mtu: ${var.vm_mtu}
            addresses:
              - ${each.value.ip}/${var.vm_subnet_mask}
            gateway4: ${var.vm_gateway}
            nameservers:
              addresses: ${jsonencode(var.vm_dns_servers)}
  - path: /usr/local/sbin/disable-nic-offload.sh
    permissions: '0755'
    content: |
      #!/bin/sh
      set -eu
      iface="$(ip route get 1.1.1.1 2>/dev/null | awk '{print $5; exit}')"
      if [ -z "$iface" ]; then
        iface="$(ip -o -4 route show to default | awk '{print $5; exit}')"
      fi
      [ -n "$iface" ] || exit 0
      ethtool -K "$iface" tso off gso off gro off tx off rx off rxvlan off txvlan off 2>/dev/null || true
  - path: /etc/systemd/system/disable-nic-offload.service
    content: |
      [Unit]
      Description=Disable NIC offloading
      After=network-online.target
      Wants=network-online.target

      [Service]
      Type=oneshot
      ExecStart=/usr/local/sbin/disable-nic-offload.sh

      [Install]
      WantedBy=multi-user.target

runcmd:
  - |
    # Install required packages with proper apt lock handling
    /usr/local/sbin/safe-apt-install.sh qemu-guest-agent curl ethtool apt-transport-https ca-certificates open-iscsi nfs-common
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent
  - sysctl --system
  - systemctl enable iscsid
  - systemctl start iscsid
  - netplan apply
  - systemctl daemon-reload
  - systemctl enable --now disable-nic-offload.service
  - |
    # Verify internet connectivity
    ok=0
    for i in $(seq 1 30); do
      if ping -c1 -W1 1.1.1.1 >/dev/null 2>&1 && curl -fsSL https://get.k3s.io >/dev/null 2>&1; then
        ok=1
        break
      fi
      sleep 5
    done
    if [ "$ok" -ne 1 ]; then
      echo "Internet connectivity check failed" >&2
      exit 1
    fi
  - |
    # Validate MTU to avoid VXLAN stalls
    ip -o link show | awk -F': ' '/e/{print $2, $3}' | head -5
    mtu=${var.vm_mtu}
    size=$((mtu - 28))
    ping -c 2 -M do -s "$size" 8.8.8.8 >/dev/null 2>&1 || echo "MTU probe failed"
  - echo "done" > /tmp/cloud-config.done
EOF
    file_name = "k3s-cp-${each.value.name}-cloud-config.yaml"
  }
}

# Cloud-init config for worker nodes
resource "proxmox_virtual_environment_file" "k3s_worker_cloud_config" {
  for_each = local.worker_nodes_indexed

  content_type = "snippets"
  datastore_id = var.vm_cloud_image_datastore
  node_name    = each.value.proxmox_node

  source_raw {
    data = <<-EOF
#cloud-config
hostname: ${each.value.name}
timezone: America/Toronto

users:
  - default
  - name: ${var.vm_user}
    groups: sudo
    shell: /bin/bash
    lock_passwd: false
    ssh_authorized_keys:
      - ${trimspace(var.ssh_public_key)}
    sudo: ALL=(ALL) NOPASSWD:ALL

chpasswd:
  expire: false
  users:
    - name: ${var.vm_user}
      password: ${var.vm_password}
      type: text

# Disable automatic package updates to prevent apt locks
# We'll handle package installation manually with proper lock handling
package_update: false
package_upgrade: false

write_files:
  - path: /usr/local/sbin/wait-for-apt.sh
    permissions: '0755'
    content: |
      #!/bin/bash
      # Wait for apt lock to be released
      set -e
      max_attempts=60
      attempt=0
      while [ $attempt -lt $max_attempts ]; do
        if ! lsof /var/lib/dpkg/lock-frontend /var/lib/apt/lists/lock /var/cache/apt/archives/lock >/dev/null 2>&1; then
          # Try to acquire lock
          if sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1; then
            sleep 2
            attempt=$((attempt + 1))
            continue
          fi
          break
        fi
        sleep 2
        attempt=$((attempt + 1))
      done
      if [ $attempt -eq $max_attempts ]; then
        echo "Timeout waiting for apt lock" >&2
        exit 1
      fi
  - path: /usr/local/sbin/safe-apt-install.sh
    permissions: '0755'
    content: |
      #!/bin/bash
      # Safely install packages with apt lock handling
      set -e
      /usr/local/sbin/wait-for-apt.sh
      export DEBIAN_FRONTEND=noninteractive
      export APT_LISTCHANGES_FRONTEND=none
      apt-get update -o Acquire::Retries=3 -o Acquire::http::Timeout=30
      apt-get install -y -o Dpkg::Options::="--force-confold" -o Dpkg::Options::="--force-confdef" "$@"
  - path: /etc/sysctl.d/99-kubernetes.conf
    content: |
      net.bridge.bridge-nf-call-iptables = 1
      net.bridge.bridge-nf-call-ip6tables = 1
      net.ipv4.ip_forward = 1
      net.ipv4.tcp_mtu_probing = 1
  - path: /etc/netplan/99-k3s-mtu.yaml
    content: |
      network:
        version: 2
        ethernets:
          all:
            match:
              name: "e*"
            dhcp4: false
            mtu: ${var.vm_mtu}
            addresses:
              - ${each.value.ip}/${var.vm_subnet_mask}
            gateway4: ${var.vm_gateway}
            nameservers:
              addresses: ${jsonencode(var.vm_dns_servers)}
  - path: /usr/local/sbin/disable-nic-offload.sh
    permissions: '0755'
    content: |
      #!/bin/sh
      set -eu
      iface="$(ip route get 1.1.1.1 2>/dev/null | awk '{print $5; exit}')"
      if [ -z "$iface" ]; then
        iface="$(ip -o -4 route show to default | awk '{print $5; exit}')"
      fi
      [ -n "$iface" ] || exit 0
      ethtool -K "$iface" tso off gso off gro off tx off rx off rxvlan off txvlan off 2>/dev/null || true
  - path: /etc/systemd/system/disable-nic-offload.service
    content: |
      [Unit]
      Description=Disable NIC offloading
      After=network-online.target
      Wants=network-online.target

      [Service]
      Type=oneshot
      ExecStart=/usr/local/sbin/disable-nic-offload.sh

      [Install]
      WantedBy=multi-user.target

runcmd:
  - |
    # Install required packages with proper apt lock handling
    /usr/local/sbin/safe-apt-install.sh qemu-guest-agent curl ethtool apt-transport-https ca-certificates open-iscsi nfs-common netcat-openbsd
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent
  - sysctl --system
  - systemctl enable iscsid
  - systemctl start iscsid
  - netplan apply
  - systemctl daemon-reload
  - systemctl enable --now disable-nic-offload.service
  - |
    # Verify internet connectivity
    ok=0
    for i in $(seq 1 30); do
      if ping -c1 -W1 1.1.1.1 >/dev/null 2>&1 && curl -fsSL https://get.k3s.io >/dev/null 2>&1; then
        ok=1
        break
      fi
      sleep 5
    done
    if [ "$ok" -ne 1 ]; then
      echo "Internet connectivity check failed" >&2
      exit 1
    fi
  - |
    # Validate MTU to avoid VXLAN stalls
    ip -o link show | awk -F': ' '/e/{print $2, $3}' | head -5
    mtu=${var.vm_mtu}
    size=$((mtu - 28))
    ping -c 2 -M do -s "$size" 8.8.8.8 >/dev/null 2>&1 || echo "MTU probe failed"
  - echo "done" > /tmp/cloud-config.done
EOF
    file_name = "k3s-worker-${each.value.name}-cloud-config.yaml"
  }
}

# K3s Control Plane VMs
resource "proxmox_virtual_environment_vm" "k3s_cp" {
  for_each = local.cp_nodes_indexed

  name      = each.value.name
  node_name = each.value.proxmox_node
  vm_id     = each.value.vmid

  description = "K3s Control Plane - ${each.value.name}"
  tags        = ["k3s", "control-plane"]

  stop_on_destroy     = false
  timeout_shutdown_vm = 5
  timeout_stop_vm     = 5

  cpu {
    cores = var.cp_cores
    type  = "host"
  }

  memory {
    dedicated = var.cp_memory
  }

  vga {
    memory = 16
    type   = "std"
  }

  disk {
    datastore_id = var.vm_storage_pool
    file_id      = proxmox_virtual_environment_download_file.ubuntu_cloud_image[each.value.proxmox_node].id
    interface    = "scsi0"
    discard      = "on"
    size         = var.cp_disk_size
  }

  network_device {
    bridge = var.vm_bridge
    model  = "virtio"
  }

  agent {
    enabled = true
    timeout = "1m"
  }

  initialization {
    datastore_id = var.vm_storage_pool

    ip_config {
      ipv4 {
        address = "${each.value.ip}/${var.vm_subnet_mask}"
        gateway = var.vm_gateway
      }
    }

    dns {
      servers = var.vm_dns_servers
    }

    user_data_file_id = proxmox_virtual_environment_file.k3s_cp_cloud_config[each.key].id
  }

  lifecycle {
    ignore_changes = [disk]
  }
}

# K3s Worker VMs
resource "proxmox_virtual_environment_vm" "k3s_worker" {
  for_each = local.worker_nodes_indexed

  name      = each.value.name
  node_name = each.value.proxmox_node
  vm_id     = each.value.vmid

  description = "K3s Worker - ${each.value.name}"
  tags        = ["k3s", "worker"]

  stop_on_destroy     = true
  timeout_shutdown_vm = 60
  timeout_stop_vm     = 60

  cpu {
    cores = var.worker_cores
    type  = "host"
  }

  memory {
    dedicated = var.worker_memory
  }

  vga {
    memory = 16
    type   = "std"
  }

  disk {
    datastore_id = var.vm_storage_pool
    file_id      = proxmox_virtual_environment_download_file.ubuntu_cloud_image[each.value.proxmox_node].id
    interface    = "scsi0"
    discard      = "on"
    size         = var.worker_disk_size
  }

  network_device {
    bridge = var.vm_bridge
    model  = "virtio"
  }

  agent {
    enabled = true
    timeout = "1m"
  }

  initialization {
    datastore_id = var.vm_storage_pool

    ip_config {
      ipv4 {
        address = "${each.value.ip}/${var.vm_subnet_mask}"
        gateway = var.vm_gateway
      }
    }

    dns {
      servers = var.vm_dns_servers
    }

    user_data_file_id = proxmox_virtual_environment_file.k3s_worker_cloud_config[each.key].id
  }

  lifecycle {
    ignore_changes = [disk]
  }
}

# Generate Ansible inventory file
resource "local_file" "ansible_inventory" {
  filename = "${path.module}/../../ansible/k3s-inventory.ini"
  content = <<-EOF
[k3s_cp]
%{ for node in var.k3s_cp_nodes ~}
${node.name} ansible_host=${node.ip} ansible_user=${coalesce(node.user, var.vm_user)} ansible_ssh_private_key_file=${var.ssh_private_key_path} ansible_ssh_common_args='-o StrictHostKeyChecking=accept-new -o ProxyCommand="ssh -i ~/.ssh/id_ed25519_homelab -o StrictHostKeyChecking=accept-new vyos@192.168.50.18 nc %h %p"'
%{ endfor ~}

[k3s_worker]
%{ for node in var.k3s_worker_nodes ~}
${node.name} ansible_host=${node.ip} ansible_user=${coalesce(node.user, var.vm_user)} ansible_ssh_private_key_file=${var.ssh_private_key_path} ansible_ssh_common_args='-o StrictHostKeyChecking=accept-new -o ProxyCommand="ssh -i ~/.ssh/id_ed25519_homelab -o StrictHostKeyChecking=accept-new vyos@192.168.50.18 nc %h %p"'
%{ endfor ~}

[k3s:children]
k3s_cp
k3s_worker
EOF
}
