# Media Stack (*arr + Jellyfin)

Docker Compose stack for media automation: Sonarr, Radarr, Prowlarr, qBittorrent, NZBGet, Jellyseerr, Jellyfin, all behind Gluetun VPN.

## Performance

**Arr apps (Sonarr, Radarr, Prowlarr, Jellyseerr, Whisparr) run outside the VPN** for faster API response. Only qBittorrent, NZBGet, Flaresolverr, and speedtest-tracker use the VPN.

1. **VM resources** – 8 GB RAM minimum, 16 GB for Jellyfin + arr stack; 4 CPU cores. Set in `terraform.tfvars`.

2. **Download clients** – Arr apps connect to qBittorrent/NZBGet via the host gateway:
   - **qBittorrent:** Host `host.docker.internal`, Port `8080`
   - **NZBGet:** Host `host.docker.internal`, Port `6789`
   - **Flaresolverr** (if used): `host.docker.internal:8191`
   - **Prowlarr:** `prowlarr:9696` (same network)

3. **Jellyseerr** – Connects to Sonarr/Radarr/Jellyfin via container names: `sonarr`, `radarr`, `jellyfin` (same network).

4. **NFS** – Media on NFS adds latency for scans/renames. Use local SSD for `/data/*` config.

5. **Resource reservations** – Sonarr and Radarr have 512M reserved, 1G limit.

**After redeploy:** Update Sonarr, Radarr, Whisparr download clients to use `host.docker.internal` as host (replaces `localhost`). Prowlarr → Settings → Apps → Flaresolverr: use `http://host.docker.internal:8191` if needed.

### Troubleshooting: Prowlarr auth error when using the domain

Prowlarr uses Basic Auth and can fail when you open it via the domain (e.g. `https://prowlarr.${DOMAIN}`) behind Traefik—browser or proxy may not send the auth header correctly.

1. **Try direct access** – Expose Prowlarr on the host: in `stacks/media/docker-compose.yml` under `prowlarr`, uncomment the `ports` block (`9696:9696`), then `docker compose up -d`. Open `http://<host-ip>:9696` in the browser and log in. If that works, the issue is domain/proxy-related.
2. **Set or re-enter credentials** – Prowlarr has no default password. First time: set a username/password when prompted. If you already set one, try clearing site data for `prowlarr.${DOMAIN}` (or use a private window) and log in again with that username/password.
3. **If you’re locked out** – On the host: edit `/data/prowlarr/config.xml`, set `<AuthenticationMethod>none</AuthenticationMethod>` (or `external` if you use a reverse-proxy auth), restart Prowlarr, then set a new password in Settings → General.
4. **Auth error when Prowlarr talks to Sonarr/Radarr** – In Prowlarr → Settings → Apps, when you add Sonarr or Radarr you must use the **exact URL** (e.g. `http://sonarr:8989` or `https://sonarr.${DOMAIN}`) and the **API key** from that app (Sonarr/Radarr → Settings → General → API Key). Wrong URL or API key causes auth errors.

## NFS Mounts

`/mnt/arr` and `/mnt/corn` are typically NFS mounts. **The NFS server must be up before the media stack starts**, or containers will see empty directories.

### Ansible deployment

When deploying with Ansible, the playbook will:
1. Install `nfs-common`
2. Create mount points `/mnt/arr` and `/mnt/corn`
3. Add fstab entries and mount (if `nfs_arr_export` / `nfs_corn_export` vars are set)
4. Wait for NFS to be available before starting containers

Set these vars when running the deploy playbook:
```bash
ansible-playbook -i ansible/inventory.ini ansible/deploy-stacks.yml \
  --extra-vars '{"stacks_to_deploy": ["core", "media"], "nfs_arr_export": "nfs-server.local:/export/arr", "nfs_corn_export": "nfs-server.local:/export/corn"}'
```

### Manual fstab (if not using Ansible vars)

Add to `/etc/fstab` on the Docker host:
```
nfs-server.local:/export/arr  /mnt/arr  nfs  _netdev,auto,x-systemd.requires=network-online.target  0  0
nfs-server.local:/export/corn /mnt/corn nfs  _netdev,auto,x-systemd.requires=network-online.target  0  0
```

### Boot order

On host reboot, ensure the NFS server comes up before or with the Docker host. If containers start with NFS down, they will see empty folders. After NFS is back up, run:
```bash
ansible-playbook -i ansible/inventory.ini ansible/deploy-stacks.yml --extra-vars '{"stacks_to_deploy": ["media"]}'
```
Or use the wait script (e.g. via cron @reboot): `scripts/wait-nfs-media.sh`

## Folder Structure

Paths depend on your NFS export and Sonarr/NZBGet config. Common layouts:

```
/mnt/arr/
├── completed/          # NZBGet/category output (if used)
│   ├── TV/             # TV shows - add as Jellyfin "Shows" library
│   └── movies/         # Movies - add as Jellyfin "Movies" library
├── downloads/          # qBittorrent & NZBGet staging (do not add to Jellyfin)
├── tv/                 # Sonarr root - final TV library (if using this path)
└── movies/             # Radarr root - final movies library
```

**Whisparr** uses a separate path by design—kept private and isolated from the main library:

```
/mnt/corn/              # Whisparr only - private, not mixed with /mnt/arr
```

## Required App Configuration

### Sonarr

1. **Settings → Media Management → Root Folders**
   - Add root folder: `/media/tv`
   - This is where completed episodes are imported

2. **Settings → Download Clients → qBittorrent**
   - Host: `host.docker.internal` (arr apps run outside VPN)
   - Port: 8080
   - Category: `sonarr` (optional)
   - **No remote path mapping needed** - both use `/downloads`

3. **Settings → Media Management → Episode Naming**
   - Use "Season folder" format: `Season 01` (puts episodes in one folder per season)
   - Already configured via API: `Season {season:00}` with rename enabled

4. **Organizing flat episodes into season folders**
   - If episodes are in separate folders (e.g. `/media/completed/TV` or `/media/staging/TV`):
   - **Wanted → Manual Import** → choose `/media/staging/TV` or `/media/downloads/completed/tv`
   - Sonarr will match files to series, move them to `/media/tv/Show Name/Season 01/`, and rename

### Radarr

1. **Settings → Media Management → Root Folders**
   - Add root folder: `/media/movies`

2. **Settings → Download Clients → qBittorrent**
   - Same as Sonarr - Host: `host.docker.internal`, Port: 8080

### qBittorrent

Uses default SavePath `/downloads/` (mounted from `/mnt/arr/downloads`). No changes needed.

If you previously used a different path, reset: **Settings → Downloads → Default Save Path** → `/downloads/`

### NZBGet

Set **Settings → Paths → DestDir** to `/downloads/completed`. Category paths:
- `Category2.DestDir=/downloads/completed/tv` (Sonarr)
- `Category1.DestDir=/downloads/completed/movies` (Radarr)
- **Whisparr (corn):** add a category and point it to corn so Whisparr downloads don’t land in arr:
  1. **Settings → Categories** (or **Paths** in some versions) – **Add** a new category.
  2. **Name:** `whisparr` (must match the category you set in Whisparr).
  3. **DestDir:** `/corn/downloads` (NZBGet has `/mnt/corn` mounted as `/corn` in the container).
  4. Save. New NZBs sent by Whisparr with category `whisparr` will then go to `/corn/downloads` (host: `/mnt/corn/downloads`) instead of arr.

### Troubleshooting: NZBGet not fully working

1. **Web UI** – Open `https://nzbget.${DOMAIN}` (or `http://host:6789`). Default login: **nzbget** / **tegbzn6789** (change in Settings → Security).

2. **Sonarr/Radarr can’t connect**
   - **Download Clients** in Sonarr/Radarr: Host `host.docker.internal`, Port `6789`, same username/password as NZBGet Web UI.
   - In NZBGet: **Settings → Security** set **ControlIP** to `0.0.0.0` (default can be `127.0.0.1`, which blocks *arr). Restart NZBGet after changing.
   - If you use HTTP (not HTTPS) from *arr, set **SecureControl** to `no` in NZBGet Security.

3. **News servers** – NZBGet needs at least one Usenet server: **Settings → News-servers** → Add your provider (host, port, username, password). Without this, downloads will not start.

4. **Paths** – DestDir and category DestDirs (see above) must match what Sonarr/Radarr expect. In Sonarr/Radarr **Remote Path Mappings** are only needed if the path *arr sees differs from NZBGet’s (e.g. different host); with `host.docker.internal` and shared `/downloads` mount, usually not required.

### Jellyfin

Media may be in different paths depending on NFS/Sonarr setup. Add libraries for where your files actually live:

| Library      | Content Type | Path                    |
|--------------|--------------|-------------------------|
| TV Shows     | Shows        | `/media/completed/TV` or `/media/tv` |
| Movies       | Movies       | `/media/completed/movies` or `/media/movies` |
| Corn         | Movies       | `/corn`                 |

1. **Dashboard → Libraries → Add Media Library** – add each path above.
2. **Remove** any library pointing only to `/media` (root) if it shows nothing.
3. **Scan libraries** – Dashboard → Libraries → ⋮ → Scan All.

If Jellyfin shows empty after NFS comes up, restart it:  
`docker restart jellyfin` (or redeploy the media stack).

### Whisparr (corn – separate from arr)

Whisparr uses `/mnt/corn` only. To keep it isolated:

1. **qBittorrent** – Set a category save path for Whisparr:
   - Tools → Options → Downloads → enable "Automatic torrent management"
   - Right‑click category `whisparr` (or create it) → Set category save path → `/corn/downloads`
   - Whisparr torrents will save to `/mnt/corn/downloads` instead of `/mnt/arr/downloads`

2. **NZBGet** – So Whisparr Usenet downloads go to corn, not arr:
   - **Settings → Categories** – Add category **Name** `whisparr`, **DestDir** `/corn/downloads`.
   - In Whisparr, when adding NZBGet as a download client, set **Category** to `whisparr`.

3. **Whisparr** – Settings → Media Management → Root Folders: add `/media` only.

4. **Whisparr** – Settings → Download Clients:
   - **qBittorrent** → **Remote Path Mappings:** Host = same as client (e.g. `host.docker.internal`), Remote = `/corn/downloads`, Local = `/media/downloads`.
   - **NZBGet** (if used) → **Remote Path Mappings:** Host = same as client (e.g. `host.docker.internal`), Remote = `/corn/downloads`, Local = `/media/downloads`.
   - So Whisparr finds completed files at `/media/downloads` (same as `/mnt/corn/downloads`).

5. **Remove** any Whisparr root folder pointing to arr paths (e.g. `/media/completed/whisparr`).

6. **Existing Whisparr content in arr** – If movies were saved to `/mnt/arr`, move them to `/mnt/corn` or remove and re-add in Whisparr after fixing the config.

**Whisparr: clean moves (hardlinks)** – Downloads and library are both under `/mnt/corn` (qBittorrent `/corn/downloads`, Whisparr root `/media`), so they’re on the same filesystem and hardlinks work:
- **Whisparr** → Settings → Media Management → **Importing** → enable **Use Hard links instead of Copy**. Imports then link instead of copy+delete (no extra space, instant).
- If **Remote Path Mapping** is wrong, Whisparr won’t find the file or will copy across paths; keep Host matching the download client host, Remote `/corn/downloads`, Local `/media/downloads`.
- If `/mnt/corn` is **NFS**, many NFS setups don’t support hardlinks; Whisparr will fall back to copy then delete (correct result, but uses extra space during import).

## Troubleshooting: Episodes Not in One Folder

- **Sonarr root folder** must be `/media/tv` (not `/downloads`)
- **Episode naming** in Sonarr: enable "Season folder" so episodes go to `Show Name/Season 01/` instead of `Show Name/Show Name S01E01/`
- **Download client path**: qBittorrent and Sonarr must both see `/downloads` - the volume mounts ensure this
- Run `docker compose up -d` after any compose changes
