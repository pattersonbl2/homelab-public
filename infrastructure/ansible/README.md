# Ansible Deployment

Deploy Docker Compose stacks to homelab VMs. **Single source of truth:** `deploy-stacks.yml`. The default entrypoint `playbook.yml` runs it with stacks: core, database, networking, media (e.g. for Terraform).

- **Remote layout:** `~/homelab/stacks/<stack_name>/` (e.g. `~/homelab/stacks/core/`), shared env at `~/homelab/stacks/env`.
- **Available stacks:** core, media, database, networking, gitea, projects, ai-tools, newt.

## Automatic Execution (Recommended)

The playbook runs **automatically** when you execute `terraform apply`. Terraform will:
1. Create the VMs
2. Wait for them to be ready
3. Automatically run the Ansible playbook for each VM
4. Clean up temporary inventory files

No manual steps required!

```bash
cd infrastructure/terraform
terraform apply
```

## Manual Execution

If you need to run the playbook manually (e.g., for testing or re-running deployment):

### Prerequisites

1. **Install Ansible** (if not already installed):
   ```bash
   brew install ansible
   ```

2. **Get VM IP addresses**:
   - Check Proxmox console for VM IPs
   - Or use: `terraform output` (if configured)
   - Or use VM hostname: `homelab-1.local`, `homelab-2.local`, etc.

### Method 1: Create Inventory File Manually

1. **Create an inventory file** (`ansible/inventory.ini`):
   ```ini
   [homelab_vms]
   homelab-1 ansible_host=192.168.1.100 ansible_user=ubuntu ansible_password=your_password ansible_ssh_common_args='-o StrictHostKeyChecking=accept-new'
   homelab-2 ansible_host=192.168.1.101 ansible_user=ubuntu ansible_password=your_password ansible_ssh_common_args='-o StrictHostKeyChecking=accept-new'
   ```

   Or use hostnames (if mDNS is working):
   ```ini
   [homelab_vms]
   homelab-1 ansible_host=homelab-1.local ansible_user=ubuntu ansible_password=your_password ansible_ssh_common_args='-o StrictHostKeyChecking=accept-new'
   ```

2. **Run the playbook**:
   ```bash
   cd ansible
   ansible-playbook -i inventory.ini playbook.yml
   ```

### Method 2: Use Dynamic Inventory (Single VM)

For a single VM, you can pass variables directly:

```bash
cd ansible
ansible-playbook -i "homelab-1.local," playbook.yml \
  -e "ansible_user=ubuntu" \
  -e "ansible_password=your_password" \
  -e "ansible_ssh_common_args='-o StrictHostKeyChecking=accept-new'"
```

Or with IP address:

```bash
ansible-playbook -i "192.168.1.100," playbook.yml \
  -e "ansible_user=ubuntu" \
  -e "ansible_password=your_password" \
  -e "ansible_ssh_common_args='-o StrictHostKeyChecking=accept-new'"
```

### Method 3: Use SSH Keys (Instead of Password)

If you've configured SSH keys:

1. **Create inventory** (`ansible/inventory.ini`):
   ```ini
   [homelab_vms]
   homelab-1 ansible_host=192.168.1.100 ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/id_rsa
   ```

2. **Run playbook**:
   ```bash
   ansible-playbook -i inventory.ini playbook.yml
   ```

## Playbook Options

### Deploy specific stacks

Use `deploy-stacks.yml` and override `stacks_to_deploy`:

```bash
# Deploy only core and media
ansible-playbook -i inventory.ini deploy-stacks.yml -e '{"stacks_to_deploy": ["core","media"]}'

# Deploy all stacks
ansible-playbook -i inventory.ini deploy-stacks.yml -e '{"stacks_to_deploy": ["core","media","database","networking","gitea","projects","ai-tools","newt"]}'
```

### Verbose output

```bash
ansible-playbook -i inventory.ini playbook.yml -v
```

### Check mode (dry run)

Test what would change without making changes:

```bash
ansible-playbook -i inventory.ini playbook.yml --check
```

### Limit to Specific Hosts

Run playbook on specific VMs only:

```bash
ansible-playbook -i inventory.ini playbook.yml --limit homelab-1
```

### Tailscale (remote access to homelab)

When Terraform creates the Tailscale LXC container (`tailscale-1`), configure it once with a [Tailscale auth key](https://login.tailscale.com/admin/settings/keys) (reusable, with “Subnet router” or “Tags” as needed):

```bash
cd ansible
ansible-playbook -i inventory.ini tailscale.yml \
  -e tailscale_auth_key=tskey-auth-XXXXX \
  -e tailscale_advertise_routes=192.168.50.0/24
```

Use your LAN subnet for `tailscale_advertise_routes` (must match `tailscale_subnet_cidr` in Terraform). Then in the [Tailscale admin console](https://login.tailscale.com/admin/machines), open the `tailscale-1` machine and **approve the advertised subnet route**. After that you can reach homelab VMs (homelab-1, etc.) from any device on your Tailnet while away from home.

### Verify Whisparr checklist (media stack)

Run the Whisparr clean-moves checklist on hosts that have the media stack:

```bash
ansible-playbook -i inventory.ini verify-whisparr-checklist.yml
ansible-playbook -i inventory.ini verify-whisparr-checklist.yml --limit homelab-1
```

The playbook copies and runs `scripts/verify-whisparr-checklist.sh` on each host. See `stacks/media/README.md` for the manual UI checklist.

## Troubleshooting

### Connection Issues

If you can't connect:
1. Check VM is running and accessible: `ping <vm_ip_or_hostname>`
2. Verify SSH access: `ssh ubuntu@<vm_ip_or_hostname>`
3. Check firewall rules on the VM
4. Ensure password authentication is enabled in VM's SSH config

### Permission Issues

The playbook uses `become: yes` (sudo). Ensure your user has sudo access:
- Default Ubuntu cloud images have passwordless sudo for the default user
- If using a custom user, ensure it's in the `sudo` group

### Ansible Not Found

If you get `ansible-playbook: command not found`:
```bash
brew install ansible
```

### Python Issues

If you see Python-related errors:
- The playbook uses `interpreter_python = auto_silent` which should auto-detect Python
- Ensure Python 3 is installed on the VMs (Ubuntu cloud images include it)

## Re-running After Changes

If you modify the playbook or Docker Compose files and want to re-run:

1. **For Terraform-managed VMs**: Run `terraform apply` again, which will trigger the playbook
2. **Manually**: Use the manual execution methods above

Note: The playbook is idempotent - running it multiple times is safe and won't cause issues.

