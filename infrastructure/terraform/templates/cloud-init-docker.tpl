#cloud-config
hostname: ${hostname}
timezone: America/Toronto

users:
  - default
  - name: ${username}
    groups: sudo, docker
    shell: /bin/bash
    ssh_authorized_keys:
      - ${ssh_public_key}
    sudo: ALL=(ALL) NOPASSWD:ALL

package_update: true
package_upgrade: true

packages:
  - ansible
  - qemu-guest-agent
  - net-tools
  - curl
  - ca-certificates
  - gnupg
  - lsb-release
  - git
  - vim
  - htop
  - ufw
  - fail2ban
  - unattended-upgrades

write_files:
  - path: /etc/docker/daemon.json
    owner: root:root
    permissions: '0644'
    content: |
      {
        "log-driver": "json-file",
        "log-opts": {
          "max-size": "10m",
          "max-file": "3"
        },
        "no-new-privileges": true,
        "userland-proxy": false
      }

  - path: /etc/fail2ban/jail.local
    owner: root:root
    permissions: '0644'
    content: |
      [sshd]
      enabled = true
      port = ssh
      filter = sshd
      maxretry = 3
      bantime = 3600
      findtime = 600

  - path: /etc/ssh/sshd_config.d/99-hardening.conf
    owner: root:root
    permissions: '0644'
    content: |
      PasswordAuthentication no
      PermitRootLogin no
      MaxAuthTries 3
      X11Forwarding no
      AllowTcpForwarding no
      ClientAliveInterval 300
      ClientAliveCountMax 2

runcmd:
  # QEMU agent
  - systemctl enable qemu-guest-agent
  - systemctl start qemu-guest-agent

  # Docker repo setup
  - mkdir -p /etc/apt/keyrings
  - curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  - chmod a+r /etc/apt/keyrings/docker.gpg
  - echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list

  # Docker install
  - apt-get update
  - apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

  # Enable Docker
  - systemctl enable docker
  - systemctl start docker

  # Firewall — allow local and lab networks, deny everything else
  - ufw default deny incoming
  - ufw default allow outgoing
  - ufw allow from 192.168.50.0/24
  - ufw allow from 10.10.10.0/24
  - ufw --force enable

  # Enable fail2ban
  - systemctl enable fail2ban
  - systemctl start fail2ban

  # Enable unattended security upgrades
  - systemctl enable unattended-upgrades

  # Restart SSH with hardened config
  - systemctl restart sshd

  # Completion marker
  - echo "done" > /tmp/cloud-config.done
