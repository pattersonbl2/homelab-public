#!/bin/bash
# scripts/lxc-veth-watchdog.sh
# Deployed to Proxmox nodes (ansible/deploy-lxc-veth-watchdog.yml) via a
# systemd timer. Detects running LXCs whose host-side veth exists but is
# no longer attached to its configured bridge, and reattaches it.
#
# Root cause (2026-07-16 outage): ifupdown2 treats a bridge's port list as
# fully declarative. Any `ifreload -a` / `systemctl restart networking` on
# the host — whether from a boot-time race, an SDN config commit, or a
# human troubleshooting at the console — rebuilds vmbr0 from
# /etc/network/interfaces and silently drops any veth that isn't listed
# there, i.e. every running container's veth. The containers themselves
# never notice: LXC doesn't re-verify bridge membership after start, so
# `pct list` keeps reporting "running" with zero connectivity. This can
# recur any time networking.service restarts while containers are up, not
# just at boot, so this runs on an ongoing timer rather than a one-shot
# boot check.
set -euo pipefail

NTFY_TOPIC="homelab-alerts"
NTFY_URL="https://ntfy.bp31app.com/${NTFY_TOPIC}"
# Optional ntfy access token (NTFY_TOKEN env or root-only /etc/ntfy-token).
# Without one the post goes out anonymously, which only works while the topic
# still grants anonymous write.
NTFY_TOKEN="${NTFY_TOKEN:-$(cat /etc/ntfy-token 2>/dev/null || true)}"
NTFY_AUTH=()
[[ -n "$NTFY_TOKEN" ]] && NTFY_AUTH=(-H "Authorization: Bearer $NTFY_TOKEN")
STATE_DIR="/run/lxc-veth-watchdog"
COOLDOWN_SECONDS=1800

mkdir -p "$STATE_DIR"

fixed=()

while read -r vmid; do
  [[ -z "$vmid" ]] && continue
  while read -r netline; do
    idx="${netline%%:*}"
    idx="${idx#net}"
    bridge=$(grep -oP 'bridge=\K[^,]+' <<<"$netline") || continue
    [[ -z "$bridge" ]] && continue
    veth="veth${vmid}i${idx}"

    link=$(ip -o link show "$veth" 2>/dev/null) || continue
    master=$(grep -oP 'master \K\S+' <<<"$link" || true)

    if [[ "$master" != "$bridge" ]]; then
      ip link set "$veth" master "$bridge"
      ip link set "$veth" up
      fixed+=("CT $vmid: $veth -> $bridge (was: ${master:-none})")
      logger -t lxc-veth-watchdog "reattached $veth to $bridge for CT $vmid (was: ${master:-none})"
    fi
  done < <(pct config "$vmid" | grep -oP '^net\d+:.*')
done < <(pct list | awk 'NR>1 && $2=="running" {print $1}')

if [[ ${#fixed[@]} -eq 0 ]]; then
  exit 0
fi

state_file="$STATE_DIR/alerted"
if [[ -f "$state_file" ]]; then
  last_alert=$(cat "$state_file")
  now=$(date +%s)
  if (( now - last_alert < COOLDOWN_SECONDS )); then
    exit 0
  fi
fi

message=$(printf '%s\n' "${fixed[@]}")
curl -s --max-time 10 -X POST "$NTFY_URL" \
  ${NTFY_AUTH[@]+"${NTFY_AUTH[@]}"} \
  -H "Title: $(hostname): reattached orphaned LXC veth(s)" \
  -H "Priority: high" \
  -d "$message" \
  > /dev/null || logger -t lxc-veth-watchdog "failed to send ntfy alert"

date +%s > "$state_file"
