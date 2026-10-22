#!/usr/bin/env python3
"""One-time setup script for Uptime Kuma v2 monitors and notifications."""

import json
import os
import sys

from uptime_kuma_api import UptimeKumaApi, MonitorType

KUMA_URL = os.environ.get("KUMA_URL", "http://uptime-kuma.uptime-kuma.svc.cluster.local:3001")
KUMA_USERNAME = os.environ["KUMA_USERNAME"]
KUMA_PASSWORD = os.environ["KUMA_PASSWORD"]
NTFY_URL = os.environ.get("NTFY_URL", "http://ntfy.ntfy.svc.cluster.local/uptime-alerts")
MONITORS_FILE = os.environ.get("MONITORS_FILE", "/config/monitors.json")

MONITOR_DEFAULTS = {
    "type": MonitorType.HTTP,
    "interval": 60,
    "timeout": 10,
    "maxretries": 3,
    "accepted_statuscodes": ["200-299"],
}


def get_or_create_group(api, group_name, existing_monitors):
    """Find existing group monitor or create one."""
    for m in existing_monitors:
        if m.get("name") == group_name and m.get("type") == MonitorType.GROUP:
            return m["id"]
    result = api.add_monitor(name=group_name, type=MonitorType.GROUP)
    print(f"  Created group: {group_name} (id={result['monitorID']})")
    return result["monitorID"]


def main():
    print(f"Connecting to Uptime Kuma at {KUMA_URL}")
    api = UptimeKumaApi(KUMA_URL)

    print("Logging in...")
    api.login(KUMA_USERNAME, KUMA_PASSWORD)

    # Create Ntfy notification
    existing_notifications = api.get_notifications()
    ntfy_exists = any(n["name"] == "Ntfy - uptime-alerts" for n in existing_notifications)

    if ntfy_exists:
        print("Ntfy notification 'Ntfy - uptime-alerts' already exists, skipping")
        notification_id = next(
            n["id"] for n in existing_notifications if n["name"] == "Ntfy - uptime-alerts"
        )
    else:
        print(f"Creating Ntfy notification channel -> {NTFY_URL}")
        result = api.add_notification(
            name="Ntfy - uptime-alerts",
            type="ntfy",
            ntfyserverurl=NTFY_URL.rsplit("/", 1)[0],
            ntfytopic=NTFY_URL.rsplit("/", 1)[1],
            ntfyPriority=5,
            isDefault=True,
            applyExisting=True,
        )
        notification_id = result["id"]
        print(f"Created notification id={notification_id}")

    # Load monitors
    with open(MONITORS_FILE) as f:
        monitors_config = json.load(f)

    # Get existing monitors to skip duplicates
    existing_monitors = api.get_monitors()
    existing_urls = {m["url"] for m in existing_monitors if m.get("url")}

    # Build group lookup
    groups = {}
    for monitor in monitors_config["monitors"]:
        group_name = monitor.get("group")
        if group_name and group_name not in groups:
            groups[group_name] = get_or_create_group(api, group_name, existing_monitors)

    # Create monitors
    created = 0
    skipped = 0
    for monitor in monitors_config["monitors"]:
        if monitor["url"] in existing_urls:
            print(f"  SKIP (exists): {monitor['name']} -> {monitor['url']}")
            skipped += 1
            continue

        print(f"  CREATE: {monitor['name']} -> {monitor['url']}")
        kwargs = {
            "name": monitor["name"],
            "url": monitor["url"],
            "notificationIDList": [notification_id],
            **MONITOR_DEFAULTS,
        }
        group_name = monitor.get("group")
        if group_name and group_name in groups:
            kwargs["parent"] = groups[group_name]

        api.add_monitor(**kwargs)
        created += 1

    print(f"\nDone! Created: {created}, Skipped: {skipped}, Total: {created + skipped}")
    api.disconnect()
    return 0


if __name__ == "__main__":
    sys.exit(main())
