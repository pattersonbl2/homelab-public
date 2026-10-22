# VyOS Router Terraform Module

This Terraform module manages the VyOS router VM that provides gateway, NAT, firewall, and DHCP services for the lab network (10.10.0.0/24).

## Features

- Standalone module - independent from K3s infrastructure
- VyOS router VM with dual network interfaces (WAN and LAN)
- Configurable VM resources (CPU, memory, disk)
- Network bridge configuration for WAN and LAN

## Prerequisites

1. VyOS ISO file uploaded to Proxmox datastore
2. Proxmox API token with appropriate permissions
3. Network bridges configured on Proxmox (vmbr0 for WAN, lab for LAN)

## Usage

1. Copy `terraform.tfvars.example` to `terraform.tfvars` and fill in your values:

```bash
cp terraform.tfvars.example terraform.tfvars
```

2. Initialize Terraform:

```bash
terraform init
```

3. Review the plan:

```bash
terraform plan
```

4. Apply the configuration:

```bash
terraform apply
```

## Configuration

The module creates a VyOS router VM with:
- **VM ID**: 200 (configurable)
- **VM Name**: vyos-gw (configurable)
- **WAN Interface**: Connected to vmbr0 bridge (DHCP)
- **LAN Interface**: Connected to lab bridge (10.10.0.1)

## Post-Deployment

After the VM is created:
1. Boot the VM and install VyOS from the ISO
2. Configure VyOS via console or Ansible (see `ansible/vyos-setup.yml`)
3. The router will provide gateway services for the lab network

## Variables

See `variables.tf` for all available configuration options.

## Outputs

- `vyos_router_info`: Information about the created VyOS router VM
