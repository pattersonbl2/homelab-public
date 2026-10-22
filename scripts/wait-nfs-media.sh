#!/bin/bash
# Wait for NFS mounts then restart media stack - run after boot or when NFS recovers
# Usage: run via cron @reboot or systemd timer

set -e
RETRIES=24
DELAY=5
MEDIA_COMPOSE="${MEDIA_COMPOSE:-/home/ubuntu/homelab/stacks/media/docker-compose.yml}"
ENV_FILE="${ENV_FILE:-/home/ubuntu/homelab/stacks/env}"

for i in $(seq 1 $RETRIES); do
  mount -a 2>/dev/null || true
  if mountpoint -q /mnt/arr 2>/dev/null; then
    echo "$(date): NFS /mnt/arr is mounted, restarting media stack"
    cd "$(dirname "$MEDIA_COMPOSE")"
    docker compose --env-file "$ENV_FILE" up -d --remove-orphans
    exit 0
  fi
  if ! grep -q '/mnt/arr' /etc/fstab 2>/dev/null; then
    echo "$(date): No fstab entry for /mnt/arr, skipping"
    exit 0
  fi
  echo "$(date): Waiting for NFS (attempt $i/$RETRIES)..."
  sleep $DELAY
done

echo "$(date): NFS /mnt/arr not available after $RETRIES retries"
exit 1
