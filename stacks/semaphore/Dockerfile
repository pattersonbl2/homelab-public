# Custom Semaphore image.
#
# Adds the dependencies needed to run Ansible against the LXC fleet via the
# community.general.proxmox_pct_remote connection plugin — which SSHes to the
# Proxmox node and runs `pct exec` into the container, so we never need root
# SSH open on the hardened LXCs (dockerhost/proxy/db-1).
#
#   - paramiko           : required by the proxmox_pct_remote connection (paramiko-based SSH)
#   - community.general  : pinned 10.3.0 — bundled 8.5.0 lacks proxmox_pct_remote,
#                          and 10.4+ redirects it to community.proxmox (breaks on
#                          the runner's ansible-core 2.16.9)
#   - community.postgresql: used by setup-db-lxc.yml
#
# Collections are installed to a dedicated path (/opt/ansible-extra/collections)
# so they don't shadow the bundled collections for other playbooks. Templates
# that need them set ANSIBLE_COLLECTIONS_PATH via the "pct-proxmox" environment.
FROM semaphoreui/semaphore:v2.10.22

USER root

COPY collections-requirements.yml /opt/ansible-extra/requirements.yml

RUN set -eux; \
    VENV="$(ls -d /opt/semaphore/apps/ansible/*/venv | head -n1)"; \
    "$VENV/bin/pip" install --no-cache-dir paramiko; \
    "$VENV/bin/ansible-galaxy" collection install -r /opt/ansible-extra/requirements.yml -p /opt/ansible-extra/collections; \
    chmod -R a+rX /opt/ansible-extra

# Restore the stock non-root user (semaphore = uid 1001)
USER 1001
