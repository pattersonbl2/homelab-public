# Local CI/CD Scripts

Automated deployment scripts for homelab infrastructure using git hooks and Ansible.

## Quick Start

### Initial Setup

Run the setup script once to install git hooks:

```bash
./scripts/setup-git-hooks.sh
```

This will:
- Install `post-commit` hook (runs after `git commit`)
- Install `post-merge` hook (runs after `git pull` or `git merge`)
- Make deployment scripts executable

### Automatic Deployment

Once hooks are installed, deployments happen automatically:

```bash
# Make changes to stacks/
git add stacks/core/docker-compose.yml
git commit -m "Update traefik config"
# → Automatically detects and deploys core stack
```

### Manual Deployment

You can also run deployments manually:

```bash
# Deploy all changed stacks
./scripts/deploy-local.sh

# Deploy specific stacks
./scripts/deploy-local.sh --stacks core,media

# Dry run (see what would be deployed)
./scripts/deploy-local.sh --dry-run

# Verbose output
./scripts/deploy-local.sh --verbose
```

## How It Works

### Change Detection

The deployment script automatically detects changes by comparing git commits:

- **Stack changes**: Files in `stacks/core/`, `stacks/media/`, etc.
- **Ansible changes**: Changes to `ansible/deploy-stacks.yml`
- **K3s changes**: Changes to `ansible/deploy-k3s-*.yml` (gitops is now at `/Users/bp31/Documents/gitops`)

### Deployment Flow

1. Git hook triggers after commit/merge
2. Script detects which stacks changed
3. Runs `ansible/deploy-stacks.yml` with detected stacks
4. If K3s deployment scripts changed, also runs `ansible/deploy-k3s-traefik.yml`
5. Logs saved to `logs/deploy-*.log`

## Options

### `deploy-local.sh` Options

- `--dry-run`: Show what would be deployed without actually deploying
- `--verbose, -v`: Enable verbose Ansible output
- `--stacks STACKS`: Deploy specific stacks (comma-separated: `core,media,database,networking`)
- `--skip-k3s`: Skip K3s deployments even if deployment scripts changed
- `--help, -h`: Show help message

### Bypassing Auto-Deployment

To skip automatic deployment for a specific commit:

```bash
SKIP_LOCAL_DEPLOY=1 git commit -m "WIP: not ready to deploy"
```

## Logs

Deployment logs are saved to:
- `logs/deploy-YYYYMMDD-HHMMSS.log` - Full deployment logs
- `/tmp/git-hook-deploy.log` - Latest hook execution (background)

View logs:
```bash
# Latest deployment log
ls -t logs/deploy-*.log | head -1 | xargs tail -f

# Background hook log
tail -f /tmp/git-hook-deploy.log
```

## Troubleshooting

### Hooks Not Running

1. Check hooks are installed:
   ```bash
   ls -la .git/hooks/post-commit .git/hooks/post-merge
   ```

2. Re-run setup:
   ```bash
   ./scripts/setup-git-hooks.sh
   ```

### Deployment Fails

1. Check Ansible is installed:
   ```bash
   ansible-playbook --version
   ```

2. Check inventory file exists:
   ```bash
   ls -la ansible/inventory.ini
   ```

3. Test manually with verbose output:
   ```bash
   ./scripts/deploy-local.sh --verbose --stacks core
   ```

### Background Deployment

Hooks run deployments in the background so they don't block git operations. Check status:

```bash
# Check if deployment is running
ps aux | grep deploy-local.sh

# View background log
tail -f /tmp/git-hook-deploy.log
```

## Examples

### Deploy Only Core Stack

```bash
./scripts/deploy-local.sh --stacks core
```

### Test Deployment (Dry Run)

```bash
./scripts/deploy-local.sh --dry-run --verbose
```

### Deploy After Pulling Changes

```bash
git pull
# post-merge hook automatically runs if stacks/ changed
```

### Skip Deployment for WIP Commit

```bash
SKIP_LOCAL_DEPLOY=1 git commit -m "WIP: testing"
```

## Sonarr TV Organization

To organize flat episode folders into `Show Name/Season 01/` structure:

1. Open Sonarr → **Wanted → Manual Import**
2. Set path to `/media/staging/TV` (episodes from completed/TV) or `/media/downloads/completed/tv`
3. Review matches, fix any incorrect series mappings
4. Click **Import** – Sonarr will move and rename into season folders

Helper script: `scripts/sonarr-organize-tv.sh` (run on host to verify config)

## Move Whisparr to Corn

To move Whisparr content from `/mnt/arr/downloads/completed/whisparr` to `/mnt/corn/whisparr`:

```bash
# On the Docker host (SSH in first)
/path/to/homelab/scripts/move-whisparr-to-corn.sh
# Moves all folders in one run. Safe to re-run if empty.
```

Or via Ansible: `ansible-playbook -i ansible/inventory.ini ansible/move-whisparr-to-corn.yml`

### Verify Whisparr clean-moves checklist

Run from repo root to validate compose paths and (on the Docker host) paths/config:

```bash
./scripts/verify-whisparr-checklist.sh
```

On the host (where `/mnt/corn` and optionally `/data/whisparr` exist), the script also checks that `/mnt/corn/downloads` exists and greps Whisparr config for hardlink and remote-path settings. Manual UI checklist is printed at the end.

To run via Ansible on media hosts:

```bash
ansible-playbook -i ansible/inventory.ini ansible/verify-whisparr-checklist.yml
ansible-playbook -i ansible/inventory.ini ansible/verify-whisparr-checklist.yml --limit homelab-1
```

## NFS / Media Stack

When the media stack uses NFS mounts (`/mnt/arr`, `/mnt/corn`), the NFS server must be up before containers start. Use `wait-nfs-media.sh` after boot or when NFS recovers:

```bash
# Run on the Docker host (or via SSH)
./scripts/wait-nfs-media.sh
```

To run automatically at boot, add to crontab on the Docker host:
```
@reboot sleep 30 && /path/to/homelab/scripts/wait-nfs-media.sh >> /var/log/wait-nfs-media.log 2>&1
```

Set `MEDIA_COMPOSE` and `ENV_FILE` if paths differ from defaults.

## Integration with GitHub Actions

This local CI/CD system works alongside your existing GitHub Actions workflows:

- **Local**: Fast feedback, runs on every commit
- **GitHub Actions**: Runs on push to `main`, uses secrets, runs in cloud

Both systems use the same Ansible playbooks, so results are consistent.
