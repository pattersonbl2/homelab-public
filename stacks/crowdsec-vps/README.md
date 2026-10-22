# CrowdSec VPS Stack

CrowdSec security stack for the Hostinger VPS, providing intrusion detection and prevention with defense-in-depth.

## Components

- **CrowdSec Engine**: Analyzes logs, detects attacks, and shares threat intelligence
- **Traefik Bouncer**: Blocks malicious IPs at the Traefik reverse proxy level (Layer 7)
- **Firewall Bouncer**: Blocks malicious IPs at the iptables level (Layer 3/4) - installed on host

## Collections Installed

- `crowdsecurity/traefik` - Traefik access log parsing and attack detection
- `crowdsecurity/http-cve` - Known HTTP vulnerabilities (Log4j, etc.)
- `crowdsecurity/http-dos` - HTTP flood/DoS detection
- `crowdsecurity/base-http-scenarios` - Common HTTP attack patterns
- `crowdsecurity/linux` - Linux system log analysis
- `crowdsecurity/sshd` - SSH brute force detection
- `crowdsecurity/appsec-virtual-patching` - Virtual patching for known CVEs
- `crowdsecurity/appsec-generic-rules` - Generic WAF rules
- `crowdsecurity/whitelist-good-actors` - Whitelist for known good bots (Google, etc.)

## Log Sources

| Source | Container Path | Type |
|--------|---------------|------|
| Traefik access logs | `/var/log/traefik/access.log` | traefik |
| System auth logs | `/var/log/host/auth.log` | syslog, linux |

## Architecture

```
Internet
    │
    ▼
┌─────────────────┐
│ Firewall Bouncer│ ← Layer 3/4 (iptables DROP)
│   (host-level)  │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│    Traefik      │ ← Layer 7 (HTTP 403)
│ + CrowdSec      │
│   Bouncer       │
└────────┬────────┘
         │
         ▼
   Backend Services

         ↑
    Log Analysis
         │
┌─────────────────┐
│ CrowdSec Engine │ → Block Decisions → Both Bouncers
│  + Console UI   │ → Discord/Slack Alerts
└─────────────────┘
```

## Deployment

Deployed automatically by `deploy-pangolin.yml`:

```bash
ansible-playbook -i inventory-vps.ini deploy-pangolin.yml
```

The bouncer key is auto-generated and stored in `/opt/crowdsec/.env`.

## Management Commands

SSH into the VPS and run:

```bash
# View decisions (blocked IPs)
docker exec crowdsec cscli decisions list

# View alerts
docker exec crowdsec cscli alerts list

# Check bouncer status
docker exec crowdsec cscli bouncers list

# View metrics
docker exec crowdsec cscli metrics

# Manually ban an IP
docker exec crowdsec cscli decisions add --ip 1.2.3.4 --reason "manual ban"

# Unban an IP
docker exec crowdsec cscli decisions delete --ip 1.2.3.4
```

## CrowdSec Console (Optional)

To enroll in the CrowdSec Console for centralized management:

1. Sign up at https://app.crowdsec.net
2. Get your enrollment key
3. Run: `docker exec crowdsec cscli console enroll <enrollment-key>`

## Troubleshooting

### Check if bouncer is connected
```bash
docker exec crowdsec cscli bouncers list
```

### View CrowdSec logs
```bash
docker logs crowdsec
docker logs crowdsec-traefik-bouncer
```

### Test detection
```bash
# Generate a test alert (from another machine)
nikto -h https://pangolin.vps.bp31app.com
```

### Restart after config changes
```bash
cd /opt/crowdsec && docker compose restart
```

## Notifications

To enable Discord or Slack notifications:

1. Edit `/opt/crowdsec/.env` and add your webhook URL:
   ```
   DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/xxx/yyy
   ```

2. Edit `/opt/crowdsec/config/profiles.yaml` and uncomment the notifications section:
   ```yaml
   notifications:
     - discord
   ```

3. Restart CrowdSec:
   ```bash
   cd /opt/crowdsec && docker compose restart crowdsec
   ```

## Firewall Bouncer (Host-level)

The firewall bouncer runs on the host (not in Docker) and blocks IPs at the iptables level before they even reach Traefik.

```bash
# Check status
systemctl status crowdsec-firewall-bouncer

# View blocked IPs in iptables
iptables -L crowdsec-blacklists -n

# View logs
journalctl -u crowdsec-firewall-bouncer -f
```
