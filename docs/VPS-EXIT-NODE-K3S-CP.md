# VPS: K3s control plane

Add the VPS as a **K3s control plane** node to your existing cluster (for HA or remote API access). Assumes the VPS is **already on your Tailscale network** (exit node set up separately via `tailscale-vps.yml` or manually).

Works on **Hetzner Cloud** (and other Ubuntu VPS providers). Use a stock Ubuntu 22.04 image.

## Prerequisites

1. **VPS** with Ubuntu 22.04 (or similar), already on Tailscale (exit node configured).
2. **SSH from this computer**  
   Use the VPS **Tailscale IP** in inventory (e.g. `REDACTED_TAILSCALE_IP`) so Ansible connects over Tailnet. If you only had console access initially:
   ```bash
   # On VPS once: add your key to ~/.ssh/authorized_keys
   # Then: ssh -i ~/.ssh/id_ed25519_homelab root@<VPS_TAILSCALE_IP>
   ```
3. **One existing K3s control plane** reachable from the VPS. K3s nodes are behind **VyOS** (192.168.50.18); the VPS reaches them via your Tailscale subnet router → VyOS → lab (10.10.10.x). Use `k3s_first_cp_url=https://10.10.10.11:6443` (same as in kubeconfig).
4. **K3s token** from the cluster:
   ```bash
   ssh ubuntu@k3s-cp-1 'sudo cat /var/lib/rancher/k3s/server/node-token'
   ```
   SSH to the lab goes through VyOS (e.g. `ProxyJump vyos@192.168.50.18`). The **VPS** reaches the first CP at 10.10.10.11 via the subnet router and VyOS.

## Inventory

Use `ansible/inventory-vps.ini` (gitignored) with the VPS Tailscale IP:

```ini
[vps]
vps-hetzner ansible_host=REDACTED_TAILSCALE_IP ansible_user=root ansible_ssh_private_key_file=~/.ssh/id_ed25519_homelab
```

## Run the playbook

```bash
ssh-add ~/.ssh/id_ed25519_homelab
cd ansible
ansible-playbook -i inventory-vps.ini vps-exit-node-k3s-cp.yml \
  -e k3s_first_cp_url=https://<FIRST_CP_TAILSCALE_IP>:6443 \
  -e k3s_token=K10...
```

- **k3s_first_cp_url**: URL of an existing control plane the VPS can reach (use Tailscale IP of k3s-cp-1).
- **k3s_token**: Token from the first control plane (see above).

## After the playbook

The VPS is a control plane node. From any node or your laptop (with kubeconfig):

```bash
kubectl get nodes
```

To use the VPS as the API endpoint (e.g. for remote access), copy `/etc/rancher/k3s/k3s.yaml` from the VPS and set `server:` to the VPS’s Tailscale IP and port 6443.

## Exit node (already set up)

The playbook does **not** install or configure Tailscale. To set up the VPS as an exit node, use `tailscale-vps.yml` first (see that playbook’s header), or configure Tailscale on the VPS manually.
