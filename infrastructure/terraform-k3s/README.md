# K3s Cluster Terraform

Terraform configuration for provisioning K3s Kubernetes cluster nodes on Proxmox.

## Architecture

- **2 Control Plane Nodes**: HA control plane with embedded etcd
  - `k3s-cp-1` on `pve` (192.168.50.176)
  - `k3s-cp-2` on `pve2` (192.168.50.26)
- **Worker Nodes**: All on `pve2`
- **Network**: `vmbr1` bridge (direct 2.5Gb pve-pve2 link), routed through VyOS at 10.10.10.1

## Prerequisites

1. Proxmox API token with VM creation permissions
2. SSH key pair for VM access
3. `vmbr1` bridge configured on both Proxmox nodes (direct link between nodes)
4. VyOS router deployed on pve with eth1 on vmbr1 (see terraform-vyos)

## Usage

### 1. Generate K3s Token

```bash
openssl rand -base64 32
```

### 2. Configure Variables

```bash
cd infrastructure/terraform-k3s
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values (including k3s_token)
```

### 3. Deploy Infrastructure

```bash
terraform init
terraform plan
terraform apply
```

K3s will be automatically installed on all nodes via cloud-init:
- Control plane nodes will form an HA cluster with embedded etcd
- Worker nodes will join the cluster automatically
- kubectl will be available on all nodes

### 4. Access the Cluster

Wait 5-10 minutes for cloud-init to complete, then verify:

```bash
ssh ubuntu@10.10.10.11
kubectl get nodes
```

### 5. Get kubeconfig (Local Access)

```bash
scp ubuntu@10.10.10.11:/home/ubuntu/.kube/config ~/.kube/k3s-config
# Edit the server URL from 127.0.0.1 to 10.10.10.11:6443
export KUBECONFIG=~/.kube/k3s-config
kubectl get nodes
```

## Node Specifications

| Node Type | Cores | Memory | Disk |
|-----------|-------|--------|------|
| Control Plane | 2 | 4GB | 50GB |
| Worker | 4 | 8GB | 100GB |

## Network Layout

```
                 ┌────────────────────┐
                 │   192.168.50.0/24  │
                 │   (Main Network)   │
                 └─────────┬──────────┘
                           │ vmbr0 (DHCP)
                    ┌──────┴──────┐
                    │    VyOS     │
                    │ (on pve)    │
                    │ eth0: DHCP  │
                    │ eth1: .1    │
                    └──────┬──────┘
                           │ vmbr1 (2.5Gb direct link pve<->pve2)
              ┌────────────┴────────────┐
              │       10.10.10.0/24     │
              │   (VyOS DHCP/Gateway)   │
              └────────────┬────────────┘
                           │
    ┌──────────────────────┼──────────────────────┐
    │                      │                      │
┌───┴────┐           ┌─────┴─────┐          ┌─────┴─────┐
│k3s-cp-1│           │ k3s-cp-2  │          │k3s-worker │
│.11 pve │           │ .12 pve2  │          │.21+ pve2  │
└────────┘           └───────────┘          └───────────┘
```

## Customization

Edit `terraform.tfvars` to:
- Add/remove worker nodes
- Change VM specifications
- Modify IP addresses
- Adjust storage settings
