# Gitea (gitea-lxc, LXC 143 @ 192.168.50.44)

Primary git hosting + container registry. Migrated off K3s 2026-07-07.

## Deployment

- Compose lives at `/root/docker-compose.yml` on the LXC with a `/root/.env`
  (GITEA_DB_PASS, SMTP_*, RESTIC_PASSWORD) and `/root/backup.sh` alongside.
  Data bind-mounted from `/data/gitea` (host) to `/data`.
- Database: PostgreSQL 17 on soundwave/db-1 (192.168.50.15), db `gitea`, role `gitea`.
- Image pinned to the data's schema version. Upgrade deliberately (one minor at a
  time is safest); Gitea runs DB migrations on startup — role `gitea` owns the
  schema so migrations work.

## Access paths

| URL | Path | Notes |
|-----|------|-------|
| https://gitea.bp31app.com | Cloudflare tunnel → cloudflared (K3s) → 192.168.50.44:3000 | canonical (ROOT_URL); registry refs `gitea.bp31app.com/bp31/*` |
| https://gitea.local.bp31app.com | Pi-hole → Traefik (proxy-lxc .33) → .44:3000 | LAN path, LE cert |
| ssh://git@192.168.50.44:2222 | direct to container sshd | ArgoCD repo access uses this |

## Migration record (2026-07-07)

- Source: K3s `gitea` namespace (helm chart 11.0.0, gitea 1.23, CNPG PG16).
- `/data` (139M: 4 repos + packages registry) copied to LXC `/data/gitea`;
  CNPG DB dumped and restored into db-1 (old orphaned docker-era `gitea` DB
  backed up first at `/var/backups/gitea-db-pre-migration-*.sql.gz` on db-1).
- `gitea admin regenerate keys` run to rebuild authorized_keys for sshd
  (K3s used the built-in SSH server which reads keys from the DB).
- ArgoCD repoURL repointed from `gitea-ssh.gitea.svc.cluster.local` to
  `192.168.50.44:2222` (same deploy key; argocd repo secret URL patched
  manually — that secret is bootstrap-level, not gitops-managed).
- K3s copy DECOMMISSIONED 2026-07-08 (apps + namespace + PVCs pruned).
  Final pre-delete backup: `/media/backup/gitea-lxc/gitea-{data,db}-20260708.*`
  on autobots. Nightly restic backups added 2026-07-08 (see below).

## Backups (nightly, added 2026-07-08)

The `gitea-backup` sidecar (restic, same flow as `stacks/backup` on
dockerhost-lxc) runs `backup.sh` at 03:15 UTC (23:15 ET):

1. `pg_dump` of the `gitea` DB from db-1 over the LAN (plain SQL, `--clean
   --if-exists`, gzipped) into the `gitea-db-dumps` volume — last 7 kept locally.
2. `restic backup` of `/data/gitea` + the dumps + `/root/.env` into
   `/media/backup/gitea-lxc/restic` on the autobots ZFS pool, reached through
   pct mount point `mp0: /media/backup/gitea-lxc,mp=/mnt/backup/gitea-lxc`.
3. Retention 7 daily / 4 weekly / 3 monthly, `restic check` on Sundays.
4. Failures push to `ntfy.bp31app.com/homelab-alerts` (no textfile collector
   on this LXC, so no Prometheus metric — unlike the dockerhost flow).

Restore sketch: `restic -r /mnt/backup/gitea-lxc/restic restore latest --target /restore`,
copy `/restore/data/gitea` back into place, `gunzip -c dump | psql` into db-1,
then `gitea admin regenerate keys` (see gotcha above). One-shot pre-migration
tarballs from 2026-07-08 remain alongside the restic repo.

## Gotchas

- cloudflared + ArgoCD reach 192.168.50.44 from the Lab net **via vyos-gw** —
  if the router is down, external gitea and ArgoCD syncs are down too.
- Registry pushes traverse the Cloudflare tunnel externally (100MB layer limit
  applies); push big layers via gitea.local.bp31app.com instead.
