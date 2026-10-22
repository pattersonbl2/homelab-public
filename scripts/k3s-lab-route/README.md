# k3s-lab-route

Keeps the Mac's static route to the K3s lab network (`10.10.10.0/24`) via the
VyOS gateway (`192.168.50.18`) correct: present and working while on the home
LAN, removed while off it.

Driven by `com.bp31.k3s-lab-route.plist` at boot, on network changes, and on a
5-minute heartbeat.

## Install

```sh
sudo ./install.sh
```

Installs the script to `/usr/local/libexec/`, the LaunchDaemon to
`/Library/LaunchDaemons/`, and a NOPASSWD sudoers drop-in so it can be run on
demand:

```sh
sudo /usr/local/libexec/k3s-lab-route.sh
```

## Why it probes instead of just checking the route exists

A route entry can survive interface churn in a state where the kernel cannot
derive a source address for it. The entry still looks perfectly correct:

```
10.10.10/24        192.168.50.18      UGSc                  en0
```

...but every connect() to the lab net fails **locally in ~0 ms**:

```
dial tcp 10.10.10.11:6443: connect: can't assign requested address
traceroute: bind: Can't assign requested address
```

The 0 ms is the tell — the packet never left the machine. Contrast a genuinely
unreachable destination, which gives an honest multi-second timeout. Binding the
source explicitly (`ping -S 192.168.50.227`, `curl --interface 192.168.50.227`)
succeeds throughout, which confirms it is source-address selection failing and
not the network.

Only delete-then-add clears it; adding alone does not. So this script probes
`10.10.10.1` (VyOS eth1) for reachability rather than trusting the routing
table, and re-lays the route when the probe fails.

Before this change the check was presence-only, so a dead route satisfied it and
every boot, network-change and heartbeat run silently no-op'd. Diagnosed
2026-09-09.

If the lab net itself is down (VyOS stopped, power cut) the re-lay is a harmless
no-op that logs once per run. The route is never removed while on the home LAN.

## Logs

```sh
log show --predicate 'process == "logger"' --last 1h | grep k3s-lab-route
```
