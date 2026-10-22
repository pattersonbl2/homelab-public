#!/bin/bash
# scripts/breakglass-watchdog.sh
# Deployed to autobots via cron; alerts if breakglass-lxc's MCP endpoint stops
# responding. Runs from a different host than breakglass-lxc on purpose.
set -euo pipefail

BREAKGLASS_HEALTH_URL="http://192.168.50.46:8787/mcp"
NTFY_TOPIC="homelab-breakglass-watchdog"
NTFY_URL="https://ntfy.bp31app.com/${NTFY_TOPIC}"
# Optional ntfy access token (NTFY_TOKEN env or root-only /etc/ntfy-token).
# Without one the post goes out anonymously, which only works while the topic
# still grants anonymous write.
NTFY_TOKEN="${NTFY_TOKEN:-$(cat /etc/ntfy-token 2>/dev/null || true)}"
NTFY_AUTH=()
[[ -n "$NTFY_TOKEN" ]] && NTFY_AUTH=(-H "Authorization: Bearer $NTFY_TOKEN")
STATE_DIR="/run/breakglass-watchdog"
COOLDOWN_SECONDS=1800

mkdir -p "$STATE_DIR"

# The endpoint requires a bearer token for a real MCP call, but an
# unauthenticated request still proves the process is up and answering
# (breakglass's own auth middleware returns 401, not a connection error).
status_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "$BREAKGLASS_HEALTH_URL" || echo "000")

if [[ "$status_code" == "401" ]]; then
  rm -f "$STATE_DIR/alerted"
  logger -t breakglass-watchdog "breakglass-lxc healthy (401 as expected)"
  exit 0
fi

logger -t breakglass-watchdog "breakglass-lxc unhealthy: got HTTP $status_code instead of 401"

if [[ -f "$STATE_DIR/alerted" ]]; then
  last_alert=$(cat "$STATE_DIR/alerted")
  now=$(date +%s)
  if (( now - last_alert < COOLDOWN_SECONDS )); then
    exit 0
  fi
fi

curl -s --max-time 10 -X POST "$NTFY_URL" \
  ${NTFY_AUTH[@]+"${NTFY_AUTH[@]}"} \
  -H "Title: breakglass-lxc unreachable" \
  -H "Priority: high" \
  -d "breakglass MCP endpoint returned HTTP ${status_code} instead of 401 — the break-glass path may be down." \
  > /dev/null || logger -t breakglass-watchdog "failed to send ntfy alert"

date +%s > "$STATE_DIR/alerted"
