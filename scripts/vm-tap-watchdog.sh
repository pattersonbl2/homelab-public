#!/bin/bash
# scripts/vm-tap-watchdog.sh
# Deployed to Proxmox nodes (ansible/deploy-vm-tap-watchdog.yml) via a
# systemd timer. Detects running VMs whose host-side tap exists but is no
# longer attached to its configured bridge, and reattaches it.
#
# Same root cause as scripts/lxc-veth-watchdog.sh (2026-07-16 outage,
# rediscovered for VM taps on 2026-07-30): ifupdown2 treats a bridge's
# port list as fully declarative. Any `ifreload -a` /
# `systemctl restart networking` on the host — boot-time race, an SDN
# config commit, or a human troubleshooting at the console — rebuilds the
# bridge from /etc/network/interfaces and silently drops any tap that
# isn't listed there, i.e. every running VM's tap. The VM itself never
# notices: qemu doesn't re-verify bridge membership after start, so
# `qm status` keeps reporting "running" with zero connectivity. This can
# recur any time networking.service restarts while VMs are up, not just
# at boot, so this runs on an ongoing timer rather than a one-shot boot
# check.
set -euo pipefail

NTFY_TOPIC="homelab-alerts"
NTFY_URL="https://ntfy.bp31app.com/${NTFY_TOPIC}"
# Optional ntfy access token (NTFY_TOKEN env or root-only /etc/ntfy-token).
# Without one the post goes out anonymously, which only works while the topic
# still grants anonymous write.
NTFY_TOKEN="${NTFY_TOKEN:-$(cat /etc/ntfy-token 2>/dev/null || true)}"
NTFY_AUTH=()
[[ -n "$NTFY_TOKEN" ]] && NTFY_AUTH=(-H "Authorization: Bearer $NTFY_TOKEN")
STATE_DIR="/run/vm-tap-watchdog"
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
    tap="tap${vmid}i${idx}"

    link=$(ip -o link show "$tap" 2>/dev/null) || continue
    master=$(grep -oP 'master \K\S+' <<<"$link" || true)

    if [[ "$master" != "$bridge" ]]; then
      ip link set "$tap" master "$bridge"
      ip link set "$tap" up
      fixed+=("VM $vmid: $tap -> $bridge (was: ${master:-none})")
      logger -t vm-tap-watchdog "reattached $tap to $bridge for VM $vmid (was: ${master:-none})"
    fi
  done < <(qm config "$vmid" | grep -oP '^net\d+:.*')
done < <(qm list | awk 'NR>1 && $2=="running" {print $1}')

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
  -H "Title: $(hostname): reattached orphaned VM tap(s)" \
  -H "Priority: high" \
  -d "$message" \
  > /dev/null || logger -t vm-tap-watchdog "failed to send ntfy alert"

date +%s > "$state_file"
