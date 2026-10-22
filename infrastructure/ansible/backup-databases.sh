#!/usr/bin/env bash
set -euo pipefail

BACKUP_DIR="/mnt/backup/db"
LOG_FILE="/var/log/backup-databases.log"
TIMESTAMP=$(date +"%Y-%m-%d_%H%M")
DUMP_FILE="${BACKUP_DIR}/all_databases_${TIMESTAMP}.sql"
RETENTION_DAYS=30

log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"
}

log "Starting database backup"

# Run pg_dumpall as postgres user
if su - postgres -c "pg_dumpall" > "$DUMP_FILE"; then
  log "pg_dumpall completed: ${DUMP_FILE}"
else
  log "ERROR: pg_dumpall failed"
  exit 1
fi

# Compress the dump
if gzip "$DUMP_FILE"; then
  log "Compressed to ${DUMP_FILE}.gz"
else
  log "ERROR: gzip compression failed"
  exit 1
fi

# Delete dumps older than retention period
DELETED=$(find "$BACKUP_DIR" -name "all_databases_*.sql.gz" -mtime +${RETENTION_DAYS} -delete -print | wc -l)
log "Deleted ${DELETED} backups older than ${RETENTION_DAYS} days"

log "Backup complete"
