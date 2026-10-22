#!/bin/bash
# temp-alert.sh — heat-wave temperature watchdog for Proxmox hosts.
# Runs from temp-alert.timer every 3 minutes; pushes to ntfy when any
# sensor crosses its threshold, with a per-sensor cooldown to avoid spam.

NTFY_URL="${NTFY_URL:-https://ntfy.bp31app.com/homelab-alerts}"
# Optional ntfy access token (NTFY_TOKEN env or root-only /etc/ntfy-token).
# Without one the post goes out anonymously, which only works while the topic
# still grants anonymous write.
NTFY_TOKEN="${NTFY_TOKEN:-$(cat /etc/ntfy-token 2>/dev/null || true)}"
NTFY_AUTH=()
[[ -n "$NTFY_TOKEN" ]] && NTFY_AUTH=(-H "Authorization: Bearer $NTFY_TOKEN")
HDD_MAX="${HDD_MAX:-50}"
NVME_MAX="${NVME_MAX:-65}"
CPU_MAX="${CPU_MAX:-80}"
GPU_MAX="${GPU_MAX:-80}"
COOLDOWN="${COOLDOWN:-1800}"   # seconds between repeat alerts per sensor
STATE_DIR=/run/temp-alert
mkdir -p "$STATE_DIR"

alert() { # $1=sensor-key  $2=message
    local key="$1" msg="$2" now last
    now=$(date +%s)
    last=$(cat "$STATE_DIR/$key" 2>/dev/null || echo 0)
    (( now - last < COOLDOWN )) && return 0
    if curl -fsS -m 15 \
        ${NTFY_AUTH[@]+"${NTFY_AUTH[@]}"} \
        -H "Title: $(hostname): temperature alert" \
        -H "Priority: high" \
        -H "Tags: thermometer,warning" \
        -d "$msg" "$NTFY_URL" >/dev/null; then
        echo "$now" > "$STATE_DIR/$key"
    fi
    logger -t temp-alert "$msg"
}

# SATA/SAS drives
for d in /dev/sd?; do
    [ -e "$d" ] || continue
    t=$(smartctl -A "$d" 2>/dev/null | awk '/Temperature_Celsius/ {print $10; exit}')
    [[ "$t" =~ ^[0-9]+$ ]] || continue
    (( t >= HDD_MAX )) && alert "hdd_${d##*/}" "Drive $d is ${t}C (threshold ${HDD_MAX}C)"
done

# NVMe drives
for d in /dev/nvme?n1; do
    [ -e "$d" ] || continue
    t=$(smartctl -A "$d" 2>/dev/null | awk '/^Temperature:/ {print $2; exit}')
    [[ "$t" =~ ^[0-9]+$ ]] || continue
    (( t >= NVME_MAX )) && alert "nvme_${d##*/}" "NVMe $d is ${t}C (threshold ${NVME_MAX}C)"
done

# CPU package temp (coretemp hwmon)
for h in /sys/class/hwmon/hwmon*; do
    [ "$(cat "$h/name" 2>/dev/null)" = "coretemp" ] || continue
    for f in "$h"/temp*_input; do
        [ -f "$f" ] || continue
        label=$(cat "${f%_input}_label" 2>/dev/null)
        [[ "$label" == Package* ]] || continue
        v=$(cat "$f" 2>/dev/null)
        [[ "$v" =~ ^[0-9]+$ ]] || continue
        t=$(( v / 1000 ))
        (( t >= CPU_MAX )) && alert "cpu_${label// /_}" "CPU $label is ${t}C (threshold ${CPU_MAX}C)"
    done
done

# NVIDIA GPU (autobots only)
if command -v nvidia-smi >/dev/null 2>&1; then
    t=$(nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader 2>/dev/null | head -1 | tr -d ' ')
    if [[ "$t" =~ ^[0-9]+$ ]] && (( t >= GPU_MAX )); then
        alert "gpu0" "GPU (RTX 3060) is ${t}C (threshold ${GPU_MAX}C)"
    fi
fi

exit 0
