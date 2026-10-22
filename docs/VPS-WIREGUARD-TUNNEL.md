# WireGuard site-to-site tunnel (VPS ↔ homelab)

Fully self-hosted private link between your VPS and homelab. No third party; you manage keys and config.

## Layout

- **Tunnel network**: `10.200.200.0/24`
- **VPS** (WireGuard server): `10.200.200.2/24`, listens on UDP 51820
- **Homelab** (WireGuard client): `10.200.200.1/24`, connects to VPS public IP

After the tunnel is up, from the VPS you can reach homelab services at `10.200.200.1` (and the homelab peer can reach the VPS at `10.200.200.2`).

## 1. Generate keys (once)

On your machine or the homelab peer:

```bash
# VPS peer (server) keys
wg genkey | tee vps_private.key | wg pubkey > vps_public.key

# Homelab peer (client) keys
wg genkey | tee homelab_private.key | wg pubkey > homelab_public.key
```

Keep private keys secret; you’ll paste public keys into the other peer’s config.

## 2. VPS config (server)

On the VPS, create `/etc/wireguard/wg0.conf` (Debian/Ubuntu: `apt install wireguard`):

```ini
[Interface]
Address = 10.200.200.2/24
ListenPort = 51820
PrivateKey = <contents of vps_private.key>

[Peer]
# Homelab peer
PublicKey = <contents of homelab_public.key>
AllowedIPs = 10.200.200.0/24, 192.168.50.0/24
```

- `AllowedIPs = 10.200.200.0/24, 192.168.50.0/24`: accept tunnel traffic and traffic to your homelab LAN (so the VPS can route to 192.168.50.x via the homelab peer if that peer advertises it).
- Start: `sudo wg-quick up wg0`  
- Enable at boot: `sudo systemctl enable wg-quick@wg0`

Open UDP 51820 in the VPS firewall.

## 3. Homelab config (client)

On a host at homelab that has a stable way to reach the internet (e.g. Proxmox host or a small VM), create `/etc/wireguard/wg0.conf`:

```ini
[Interface]
Address = 10.200.200.1/24
PrivateKey = <contents of homelab_private.key>

[Peer]
# VPS
PublicKey = <contents of vps_public.key>
Endpoint = VPS_PUBLIC_IP:51820
AllowedIPs = 10.200.200.0/24
PersistentKeepalive = 25
```

- Replace `VPS_PUBLIC_IP` with the VPS’s public IP or hostname.
- `PersistentKeepalive` helps when the homelab peer is behind NAT.

Start: `sudo wg-quick up wg0`; enable at boot: `sudo systemctl enable wg-quick@wg0`.

## 4. Routing (optional)

- **VPS → homelab LAN**: On the homelab WireGuard host, enable IP forwarding and (if needed) NAT or routing so that traffic from `10.200.200.2` to `192.168.50.0/24` is forwarded to the LAN. Then the VPS can reach e.g. `192.168.50.97` (homelab-1).
- **Homelab → VPS**: The VPS is already at `10.200.200.2`; no extra routing needed on the VPS for that.

## 5. Test

From the VPS:

```bash
ping 10.200.200.1
# If routing is set: ping 192.168.50.97
```

From the homelab WireGuard host:

```bash
ping 10.200.200.2
```

## Automation

You can add an Ansible playbook or role to drop these configs (with templates and vars for keys and IPs) and start `wg-quick@wg0`; keep private keys in Ansible Vault or a secrets manager.
