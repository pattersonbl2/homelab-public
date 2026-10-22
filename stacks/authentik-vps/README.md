# Authentik VPS Stack

Identity provider and SSO for the VPS infrastructure. Protects services exposed through Pangolin/Traefik with forward authentication.

## Components

| Service | Purpose | Port |
|---------|---------|------|
| **authentik-server** | Main authentication server | 9000, 9443 |
| **authentik-worker** | Background task processor | - |
| **authentik-postgres** | PostgreSQL database | 5432 (internal) |
| **authentik-redis** | Session/cache storage | 6379 (internal) |

## Deployment

Deployed via `deploy-pangolin.yml` alongside Pangolin, Pi-hole, and CrowdSec:

```bash
ansible-playbook -i inventory-vps.ini deploy-pangolin.yml
```

## Initial Setup

1. After deployment, access Authentik at `https://auth.vps.bp31app.com/if/flow/initial-setup/`
2. Create your admin account
3. Configure the embedded outpost for Traefik integration

## Traefik Integration

The stack integrates with Traefik using forward authentication middleware.

### Protecting Services

Add the `authentik` middleware to any route in `dynamic_config.yml`:

```yaml
routers:
  my-protected-service:
    rule: "Host(`service.vps.bp31app.com`)"
    service: my-service
    middlewares:
      - authentik  # Add this
      - crowdsec
    entryPoints:
      - websecure
    tls:
      certResolver: letsencrypt
```

### Creating Applications in Authentik

1. Go to **Applications** → **Create**
2. Choose **Proxy Provider** for Traefik forward auth
3. Set external host to the service URL
4. Configure the embedded outpost to use the provider

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `AUTHENTIK_POSTGRES_USER` | PostgreSQL username | `authentik` |
| `AUTHENTIK_POSTGRES_PASSWORD` | PostgreSQL password | **Required** |
| `AUTHENTIK_POSTGRES_DB` | Database name | `authentik` |
| `AUTHENTIK_SECRET_KEY` | Secret key for encryption | **Required** |

Generate secrets:

```bash
# Secret key
openssl rand -hex 50

# Postgres password
openssl rand -base64 24
```

## Network Architecture

```
Internet
    │
    ▼
┌─────────────────────────────────────────────────────┐
│                    Traefik                          │
│  (forward auth to Authentik for protected routes)  │
└─────────────────────────────────────────────────────┘
    │                    │
    │ /outpost.goauthentik.io/*
    │                    │
    ▼                    ▼
┌─────────────┐    ┌─────────────────────────────────┐
│  Authentik  │◄───│      Protected Services          │
│  (port 9000)│    │  (Jellyfin, Gitea, Grafana...)  │
└─────────────┘    └─────────────────────────────────┘
```

## Updating

```bash
cd /opt/authentik
docker compose pull
docker compose up -d
```

## Pangolin SSO Integration

Authentik can be configured as the identity provider for Pangolin, enabling SSO login.

### Quick Setup with Terraform

```bash
cd infrastructure/terraform-authentik

# Copy and configure
cp terraform.tfvars.example terraform.tfvars
# Edit with your Authentik API token (Admin > System > Tokens)

terraform init
terraform apply

# View configuration values for Pangolin
terraform output pangolin_setup_instructions
```

See [infrastructure/terraform-authentik/README.md](../../infrastructure/terraform-authentik/README.md) for full documentation.

## Troubleshooting

Check logs:

```bash
docker logs authentik-server
docker logs authentik-worker
```

Verify database connection:

```bash
docker exec -it authentik-postgres psql -U authentik -c '\l'
```
