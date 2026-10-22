#!/bin/bash
# scripts/gpu-watchdog.sh
# Deployed to autobots via cron; alerts if the RTX 3060 drops off the PCI
# bus again (Xid 79) the way it did before this was noticed manually.
set -euo pipefail

NTFY_TOPIC="homelab-gpu-watchdog"
NTFY_URL="https://ntfy.bp31app.com/${NTFY_TOPIC}"
# Optional ntfy access token (NTFY_TOKEN env or root-only /etc/ntfy-token).
# Without one the post goes out anonymously, which only works while the topic
# still grants anonymous write.
NTFY_TOKEN="${NTFY_TOKEN:-$(cat /etc/ntfy-token 2>/dev/null || true)}"
NTFY_AUTH=()
[[ -n "$NTFY_TOKEN" ]] && NTFY_AUTH=(-H "Authorization: Bearer $NTFY_TOKEN")
STATE_DIR="/run/gpu-watchdog"
COOLDOWN_SECONDS=1800

mkdir -p "$STATE_DIR"

if nvidia-smi > /dev/null 2>&1; then
  rm -f "$STATE_DIR/alerted"
  logger -t gpu-watchdog "RTX 3060 healthy"
  exit 0
fi

logger -t gpu-watchdog "nvidia-smi failed - GPU may have fallen off the bus"

if [[ -f "$STATE_DIR/alerted" ]]; then
  last_alert=$(cat "$STATE_DIR/alerted")
  now=$(date +%s)
  if (( now - last_alert < COOLDOWN_SECONDS )); then
    exit 0
  fi
fi

curl -s --max-time 10 -X POST "$NTFY_URL" \
  ${NTFY_AUTH[@]+"${NTFY_AUTH[@]}"} \
  -H "Title: RTX 3060 unreachable on autobots" \
  -H "Priority: high" \
  -d "nvidia-smi is failing on autobots - the local_worker model on llm-lxc is likely running CPU-only or down. Check dmesg for Xid errors." \
  > /dev/null || logger -t gpu-watchdog "failed to send ntfy alert"

date +%s > "$STATE_DIR/alerted"
