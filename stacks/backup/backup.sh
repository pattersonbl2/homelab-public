#!/usr/bin/env bash
set -euo pipefail

export RESTIC_REPOSITORY="${RESTIC_REPOSITORY:-/mnt/backup/docker}"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

# Initialize repo if not already initialized
if ! restic snapshots &>/dev/null; then
  log "Initializing restic repository at ${RESTIC_REPOSITORY}"
  restic init
fi

log "Starting backup"

restic backup \
  --tag docker-backup \
  --exclude '*.tmp' \
  --exclude '*.log' \
  /volumes \
  /env-file

log "Backup complete"

# Apply retention policy
log "Applying retention policy"
restic forget \
  --tag docker-backup \
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

# ─── Offsite backup to Backblaze B2 ───────────────────────────────────────────
if [ -n "${B2_BUCKET:-}" ] && [ -n "${RESTIC_B2_PASSWORD:-}" ] && [ -n "${B2_ACCOUNT_ID:-}" ]; then
  log "Starting B2 offsite backup..."

  RESTIC_REPOSITORY="b2:${B2_BUCKET}:/restic" \
  RESTIC_PASSWORD="${RESTIC_B2_PASSWORD}" \
  restic backup /volumes /env-file \
    --tag docker-volumes \
    --tag b2-offsite \
    --exclude='*.tmp' \
    --exclude='*.log' \
    --exclude='*/lost+found' \
    --verbose

  RESTIC_REPOSITORY="b2:${B2_BUCKET}:/restic" \
  RESTIC_PASSWORD="${RESTIC_B2_PASSWORD}" \
  restic forget \
    --keep-daily 7 \
    --keep-weekly 4 \
    --keep-monthly 3 \
    --prune

  log "B2 offsite backup complete."
else
  log "B2 credentials not configured — skipping offsite backup."
fi

# Write Prometheus metric
METRIC_FILE="/textfile/backup_last_success.prom"
cat > "${METRIC_FILE}" <<PROM
# HELP backup_last_success_timestamp Unix timestamp of last successful backup.
# TYPE backup_last_success_timestamp gauge
backup_last_success_timestamp $(date +%s)
PROM

log "Prometheus metric written to ${METRIC_FILE}"
log "Backup job finished successfully"
