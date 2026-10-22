#!/usr/bin/env bash
set -euo pipefail

export RESTIC_REPOSITORY="${RESTIC_REPOSITORY:-/mnt/backup/gitea-lxc/restic}"

# gitea-lxc has no node-exporter textfile collector, so failures alert via ntfy
# (same channel as the Proxmox temp-alert watchdog) instead of a Prometheus metric.
NTFY_URL="${NTFY_URL:-https://ntfy.bp31app.com/homelab-alerts}"
# Optional ntfy access token (NTFY_TOKEN env or root-only /etc/ntfy-token).
# Without one the post goes out anonymously, which only works while the topic
# still grants anonymous write.
NTFY_TOKEN="${NTFY_TOKEN:-$(cat /etc/ntfy-token 2>/dev/null || true)}"
NTFY_AUTH=()
[[ -n "$NTFY_TOKEN" ]] && NTFY_AUTH=(-H "Authorization: Bearer $NTFY_TOKEN")

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

alert() {
  curl -fsS -m 10 \
    ${NTFY_AUTH[@]+"${NTFY_AUTH[@]}"} \
    -H "Title: gitea-lxc backup FAILED" \
    -H "Priority: high" \
    -H "Tags: rotating_light" \
    -d "$1" \
    "${NTFY_URL}" >/dev/null || true
}

trap 'alert "backup.sh failed at line ${LINENO} - see /var/log/backup.log in the gitea-backup container on LXC 143"' ERR

# Initialize repo if not already initialized
if ! restic snapshots &>/dev/null; then
  log "Initializing restic repository at ${RESTIC_REPOSITORY}"
  restic init
fi

# ─── Nightly pg_dump of the gitea DB (db-1 / 192.168.50.15) ──────────────────
# Connection comes from PGHOST/PGUSER/PGDATABASE/PGPASSWORD in the environment.
DUMP_FILE="/dumps/gitea-$(date +%Y%m%d-%H%M).sql.gz"
log "Dumping database '${PGDATABASE}' from ${PGHOST} to ${DUMP_FILE}"
pg_dump --clean --if-exists | gzip > "${DUMP_FILE}"
gzip -t "${DUMP_FILE}"
DUMP_SIZE=$(stat -c%s "${DUMP_FILE}")
if [ "${DUMP_SIZE}" -lt 10240 ]; then
  log "ERROR: dump is suspiciously small (${DUMP_SIZE} bytes) - refusing to continue"
  exit 1
fi
log "DB dump complete (${DUMP_SIZE} bytes)"

# Keep a week of raw dumps locally; restic snapshots hold the longer history
find /dumps -name 'gitea-*.sql.gz' -mtime +7 -delete

log "Starting restic backup"
restic backup \
  --tag gitea-backup \
  --exclude '*.tmp' \
  /data/gitea \
  /dumps \
  /env-file

log "Backup complete"

log "Applying retention policy"
restic forget \
  --tag gitea-backup \
  --keep-daily 7 \
  --keep-weekly 4 \
  --keep-monthly 3 \
  --prune

log "Retention policy applied"

# Run integrity check on Sundays
if [ "$(date +%u)" -eq 7 ]; then
  log "Running weekly integrity check"
  restic check
  log "Integrity check complete"
fi

log "Backup job finished successfully"
