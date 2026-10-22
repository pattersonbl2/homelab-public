# Extending the Homelab with a VPS

Use a VPS to extend your homelab: public ingress, CI, backups, monitoring, or a private link—without opening ports at home. Connect the VPS to the homelab with a **self-hosted tunnel** (Tailscale or WireGuard). The guides assume generic Ubuntu VPS (e.g. **Hetzner Cloud**); no provider-specific config required.

## Using the VPS's bandwidth

The VPS often has a faster or more stable link than your home connection. You can use that in three main ways:

| Approach | How it uses VPS bandwidth | Best for |
|----------|---------------------------|----------|
| **Tailscale exit node** | Your phone/laptop choose the VPS as "exit node"; all internet traffic goes device → Tailscale → VPS → internet. You get the VPS’s upload/download for browsing, streaming, etc. | Better speed when away from home, or a different egress IP. |
| **Reverse proxy (public ingress)** | Put the VPS in front of a homelab service (e.g. Jellyfin). Traffic: user → VPS (fast) → tunnel → homelab. The VPS uses its bandwidth for the last mile to users; the tunnel leg is still limited by home upload. | Stable domain, TLS, and better peering to users; helps if home upload is decent. |
| **Download proxy** | Run downloads on the VPS (big files, torrents, etc.) where the VPS has a fast pipe, then sync results to homelab over the tunnel (rsync, scp, or a sync job). | Pulling large files without stressing home download or when home is slow. |

Details for each are in the use cases and tunnel sections below.

## Use cases

| Use case | What the VPS does | Tunnel role |
|----------|-------------------|-------------|
| **Public ingress** | Expose selected services (Jellyfin, Gitea, Homepage) with a stable IP/domain and TLS. Traffic: internet → VPS → tunnel → homelab. | VPS runs reverse proxy (Caddy/Nginx); tunnel brings traffic to homelab. |
| **CI / deploy** | Run Gitea Actions or GitHub runners on the VPS; jobs reach homelab over the tunnel to deploy stacks or run Ansible. | VPS and homelab on same virtual network (Tailscale or WireGuard). |
| **Offsite backup** | Sync backups (Proxmox, TrueNAS, DB dumps) from homelab to VPS. | Tunnel gives homelab a private path to the VPS. |
| **Monitoring / uptime** | Run Uptime Kuma or Prometheus on the VPS; checks hit homelab services over the tunnel. | Same as above. |
| **Exit node / fallback** | Use the VPS as a Tailscale exit node so traffic can egress from the VPS when the homelab subnet isn’t available. | Tailscale on VPS, enable exit node. |
| **Dev / staging** | Light staging or a small API on the VPS that talks to homelab (e.g. webhooks, APIs). | Tunnel for private homelab ↔ VPS traffic. |

## Self-hosted tunnel options

### Option A: Tailscale (easiest)

You already use Tailscale for remote access. Add the **VPS to the same Tailnet** so it can reach the homelab LAN (via your existing subnet router) and vice versa.

- **No open ports** at home or on the VPS for Tailscale.
- **One Tailnet**: VPS gets a Tailscale IP (e.g. `100.x.x.x`); homelab can reach it, and VPS can reach `192.168.50.0/24` once the subnet route is approved.
- **Optional**: Enable the VPS as an **exit node** in the Tailscale admin UI for egress through the VPS.

**Steps:**

1. On the VPS (Ubuntu/Debian):
   ```bash
   curl -fsSL https://tailscale.com/install.sh | sh
   tailscale up --authkey=tskey-auth-XXXXX
   ```
   Or use the [Tailscale-on-VPS playbook](../ansible/tailscale-vps.yml) with `-e tailscale_exit_node=true`.
2. In [Tailscale Admin](https://login.tailscale.com/admin/machines), open the VPS → **Edit route settings** → enable **Exit node** and approve it.
3. On your phone/laptop (Tailscale app): choose **Use exit node** → select the VPS. Your device’s internet traffic now egresses via the VPS (using its bandwidth).
4. From homelab (or your laptop on Tailnet), reach the VPS by its Tailscale hostname or IP (e.g. `ssh user@vps-tailscale-name`).

To automate with Ansible, add the VPS to inventory under `[vps_tailscale]` and run the [Tailscale-on-VPS playbook](../ansible/tailscale-vps.yml).

---

### Option B: WireGuard (fully self-hosted)

A **site-to-site WireGuard VPN** gives a private link between the VPS and the homelab with no third party. You run a WireGuard peer at home (e.g. on a VM or the Proxmox host) and one on the VPS.

- **No SaaS**: Only your VPS and your homelab; keys stay with you.
- **Static private IPs**: e.g. homelab peer `10.200.200.1`, VPS peer `10.200.200.2`; then route or proxy over that.

**Example layout:**

- **VPS**: WireGuard interface `wg0`, IP `10.200.200.2/24`, listens on UDP (e.g. 51820).
- **Homelab**: WireGuard interface `wg0`, IP `10.200.200.1/24`; initiates to VPS public IP.

Traffic homelab ↔ VPS goes over the tunnel. You can run a reverse proxy on the VPS that forwards to `10.200.200.1:80` (homelab).

Sample configs and step-by-step setup: [VPS-WIREGUARD-TUNNEL.md](VPS-WIREGUARD-TUNNEL.md).

---

## Recommendation

- **Start with Tailscale**: add the VPS to your Tailnet and use it for SSH, internal services, and (optionally) exit node or a small reverse proxy.
- **Add WireGuard** if you want a fully self-hosted, no-SaaS link (e.g. for backups or a dedicated proxy path).

After the tunnel is up, use the VPS for one or more of the use cases above (public ingress, CI, backup, monitoring, etc.).

---

## Exit node + K3s control plane on the VPS

To turn the VPS into a **Tailscale exit node** and add it as a **K3s control plane** to your existing cluster, see [VPS-EXIT-NODE-K3S-CP.md](VPS-EXIT-NODE-K3S-CP.md) and use the [vps-exit-node-k3s-cp.yml](../ansible/vps-exit-node-k3s-cp.yml) playbook.
