#!/bin/sh
# Maintain the static route to the K3s lab network (10.10.10.0/24) via the
# VyOS gateway on the home LAN. Safe to run at any time:
#   - On the home LAN (192.168.50.18 directly reachable): adds the route,
#     and re-lays it if the existing one is present but not working.
#   - Anywhere else: removes a stale copy of the route if we added one,
#     and never touches routes owned by anything else (VPNs etc).
#
# Installed to /usr/local/libexec/k3s-lab-route.sh by install.sh and driven
# by /Library/LaunchDaemons/com.bp31.k3s-lab-route.plist (boot + network
# changes + 5-min heartbeat). Can also be run on demand:
#   sudo /usr/local/libexec/k3s-lab-route.sh

NET=10.10.10.0/24
NET_ADDR=10.10.10.0
GW=192.168.50.18
# VyOS eth1 — the lab-side gateway address. Up whenever the lab net works,
# and it is the one lab host that is not a VM that might be shut down.
PROBE=10.10.10.1

# The gateway is "on-link" when route lookup resolves it with no intermediate
# gateway hop — i.e. the Mac has an address on the home LAN right now.
gw_on_link() {
    out=$(/sbin/route -n get "$GW" 2>/dev/null) || return 1
    echo "$out" | grep -q '^ *gateway:' && return 1
    echo "$out" | grep -q '^ *interface:'
}

# Current route for the lab net, only if it is our specific /24 via our GW
# (route get falls back to the default route when no specific route exists,
# so check the destination matches before trusting the answer).
have_our_route() {
    out=$(/sbin/route -n get -net "$NET" 2>/dev/null) || return 1
    echo "$out" | grep -q "destination: $NET_ADDR" || return 1
    echo "$out" | grep -q "gateway: $GW"
}

# Presence is NOT health. A route entry can survive interface churn in a state
# where the kernel cannot derive a source address for it: the entry still looks
# correct in `netstat -rn`, but every connect() to the lab net fails locally in
# ~0ms with "can't assign requested address" and no packet ever leaves the Mac.
# Only delete+re-add clears it, so probe reachability rather than trusting the
# routing table. Seen 2026-09-09; the old presence-only check meant boot,
# network-change and heartbeat runs all silently no-op'd against a dead route.
route_works() {
    /sbin/ping -c 1 -t 2 -o "$PROBE" >/dev/null 2>&1
}

relay_route() {
    /sbin/route -n delete -net "$NET" "$GW" >/dev/null 2>&1
    if /sbin/route -n add -net "$NET" "$GW" >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

if gw_on_link; then
    if ! have_our_route; then
        if /sbin/route -n add -net "$NET" "$GW" >/dev/null 2>&1; then
            /usr/bin/logger -t k3s-lab-route "added route $NET via $GW"
        fi
    elif ! route_works; then
        # Route is present but the lab net does not answer. Re-lay it once.
        # If the lab net itself is down (VyOS stopped, power cut) this is a
        # harmless no-op that logs once per run; it never removes the route.
        if relay_route; then
            if route_works; then
                /usr/bin/logger -t k3s-lab-route "re-laid stale route $NET via $GW (was present but unusable)"
            else
                /usr/bin/logger -t k3s-lab-route "re-laid route $NET via $GW but $PROBE still unreachable (lab net down?)"
            fi
        fi
    fi
else
    if have_our_route; then
        if /sbin/route -n delete -net "$NET" "$GW" >/dev/null 2>&1; then
            /usr/bin/logger -t k3s-lab-route "removed stale route $NET via $GW (off home LAN)"
        fi
    fi
fi

exit 0
