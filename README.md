# homelab

The infrastructure behind [ark31.info](https://ark31.info) and my home lab, in the open.

This is a **sanitised public copy** of my private monorepo. It is the code my blog posts
point at: Terraform for the VMs, Ansible for config, Docker Compose stacks for the
services that do not live in Kubernetes, and the full GitOps tree that ArgoCD reconciles.

It replaces two older repos, `pattersonbl2/gitops` and `pattersonbl2/homelab`, which were
merged into one and taken private. If a post sent you to either of those, this is where
their contents went.

## Structure

```
infrastructure/
  terraform/            Docker host VM provisioning on Proxmox
  terraform-k3s/        K3s cluster provisioning
  terraform-truenas/    TrueNAS VM
  terraform-vyos/       VyOS router
  terraform-cloudflare/ DNS, tunnels, Turnstile
  terraform-grafana/    Dashboards as code
  terraform-authentik/  SSO providers and applications
  modules/proxmox-vm/   Reusable VM module
  ansible/              Host configuration
ansible/                Playbooks (Tailscale, K3s nodes)
kubernetes/
  apps/                 ArgoCD Application definitions
  argocd/               ArgoCD itself
  infrastructure/       Per-service manifests and Helm values
stacks/                 Docker Compose stacks — Traefik, media, Gitea, Pi-hole, …
scripts/                Local CI/CD via git hooks, network isolation checks
docs/ARCHITECTURE.md    Diagrams of Proxmox, the network, K3s and the backup flow
```

## What is not here

This copy is built from the private repo by a script, not maintained by hand. It leaves out:

- **Secrets of every kind.** SOPS files, SealedSecrets, `.env` files, Terraform state and
  `.tfvars`. The `*.example` files that show the required shape are kept.
- **Routable IP addresses.** My home IP, the two VPS addresses and the Tailscale addresses
  are replaced with `REDACTED_*` markers. RFC1918 addresses are left intact — they are
  what makes the network config readable, and they are not a secret.
- **Internal planning documents** and two private application services.

RFC1918 addresses, SSH *public* keys and the DKIM *public* key are published on purpose.

## Reading it

Start with [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md). The things most people come
here for:

| You want | Look at |
|---|---|
| Prometheus, Alertmanager rules, Loki | `kubernetes/infrastructure/monitoring/` |
| Grafana dashboards as code | `infrastructure/terraform-grafana/dashboards/` |
| The ArgoCD app-of-apps | `kubernetes/apps/` |
| How a VM gets built | `infrastructure/modules/proxmox-vm/` |
| sre-reflex, the alert triage bot | `kubernetes/infrastructure/sre-reflex/` |

The bot itself lives in [pattersonbl2/sre-reflex](https://github.com/pattersonbl2/sre-reflex).

## Related writing

- [Homelab, end to end](https://ark31.info/posts/homelab-end-to-end-2026/)
- [A monitoring deep dive](https://ark31.info/posts/homelab-monitoring-deep-dive/)
- [K3s deep dive](https://ark31.info/posts/k3s-deep-dive/)
