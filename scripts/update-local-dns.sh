#!/bin/bash
set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
K3S_INVENTORY="${REPO_ROOT}/ansible/k3s-inventory.ini"
STACKS_DIR="${REPO_ROOT}/stacks"
ENV_FILE="${STACKS_DIR}/env"
HOSTS_FILE="/etc/hosts"
START_MARKER="## Homelab Hosts Start"
END_MARKER="## Homelab Hosts End"

# Remote Docker Host Configuration
DOCKER_HOST_IP="192.168.50.97"
SSH_USER="ubuntu"
SSH_KEY="${HOME}/.ssh/id_ed25519_homelab"
SSH_OPTS="-i ${SSH_KEY} -o StrictHostKeyChecking=accept-new"

# Pi-hole Configuration
PIHOLE_CONTAINER="pihole"
PIHOLE_CONFIG_FILE="99-homelab.conf"
TEMP_CONFIG_FILE="/tmp/${PIHOLE_CONFIG_FILE}"

echo "Generating DNS configuration..."

NEW_BLOCK="$START_MARKER"
NEW_BLOCK+=$'\n'

DNSMASQ_CONFIG=""

# 1. Parse K3s Inventory
if [[ -f "$K3S_INVENTORY" ]]; then
    echo "Reading K3s nodes from $K3S_INVENTORY..."
    while read -r line; do
        if [[ "$line" =~ ^[[:space:]]*$ ]] || [[ "$line" =~ ^[[:space:]]*# ]] || [[ "$line" =~ ^\[ ]]; then
            continue
        fi
        if [[ "$line" =~ ansible_host= ]]; then
            HOSTNAME=$(echo "$line" | awk '{print $1}')
            IP=$(echo "$line" | grep -o 'ansible_host=[^ ]*' | cut -d= -f2)
            
            # For /etc/hosts
            NEW_BLOCK+="${IP} ${HOSTNAME}"$'\n'
            
            # For Pi-hole (dnsmasq)
            DNSMASQ_CONFIG+="address=/${HOSTNAME}/${IP}"$'\n'
            
            echo "  Found K3s node: $HOSTNAME -> $IP"
        fi
    done < "$K3S_INVENTORY"
fi

# 2. Parse Docker Compose Services
if [[ -f "$ENV_FILE" ]] && [[ -d "$STACKS_DIR" ]]; then
    echo "Reading Docker services from $STACKS_DIR..."
    
    # Read DOMAIN from env file
    DOMAIN_VAL=$(grep "^DOMAIN=" "$ENV_FILE" | cut -d= -f2 | tr -d '"' | tr -d "'")
    
    if [[ -n "$DOMAIN_VAL" ]]; then
        echo "  Base domain: $DOMAIN_VAL"
        echo "  Using Docker Host IP: $DOCKER_HOST_IP"
        
        # Find all docker-compose.yml files
        while IFS= read -r file; do
            # Extract Host rules
            HOSTS=$(grep -o 'Host(`[^`]*`)' "$file" | sed 's/Host(`//;s/`)//')
            
            for host in $HOSTS; do
                # Replace ${DOMAIN} and {{ env "DOMAIN" }} (Traefik Go template)
                FINAL_HOST="${host//\$\{DOMAIN\}/$DOMAIN_VAL}"
                FINAL_HOST="${FINAL_HOST//\{\{ env \"DOMAIN\" \}\}/$DOMAIN_VAL}"
                
                # Check if already added to avoid duplicates
                if ! echo "$NEW_BLOCK" | grep -q " $FINAL_HOST$"; then
                    # For /etc/hosts
                    NEW_BLOCK+="${DOCKER_HOST_IP} ${FINAL_HOST}"$'\n'
                    
                    # For Pi-hole (dnsmasq)
                    DNSMASQ_CONFIG+="address=/${FINAL_HOST}/${DOCKER_HOST_IP}"$'\n'
                    
                    echo "  Found Service: $FINAL_HOST"
                fi
            done
        done < <(find "$STACKS_DIR" \( -name "docker-compose.yml" -o -name "traefik.yml" -o -path "*/dynamic/*.yml" \) -type f)
    else
        echo "  Warning: DOMAIN not found in $ENV_FILE"
    fi
fi

NEW_BLOCK+="$END_MARKER"

# --- Update Local /etc/hosts ---
echo ""
echo "--- Updating Local /etc/hosts ---"
if [[ $(echo "$NEW_BLOCK" | wc -l) -le 3 ]]; then
    echo "No hosts found to add."
else
    echo "Updating $HOSTS_FILE (requires sudo)..."
    
    # Check if we have sudo access without password or if we are root
    if sudo -n true 2>/dev/null || [[ $EUID -eq 0 ]]; then
        SUDO_CMD="sudo"
        [[ $EUID -eq 0 ]] && SUDO_CMD=""
    else
        echo "Please enter your sudo password if prompted:"
        SUDO_CMD="sudo"
    fi

    # Backup hosts file
    $SUDO_CMD cp "$HOSTS_FILE" "${HOSTS_FILE}.bak"

    # Remove existing block if present
    if grep -q "$START_MARKER" "$HOSTS_FILE"; then
        echo "Removing existing Homelab block..."
        $SUDO_CMD sed -i.tmp "/$START_MARKER/,/$END_MARKER/d" "$HOSTS_FILE"
        $SUDO_CMD rm "${HOSTS_FILE}.tmp"
    fi

    # Append new block
    echo "$NEW_BLOCK" | $SUDO_CMD tee -a "$HOSTS_FILE" > /dev/null
    echo "Done! /etc/hosts updated."
fi

# --- Update Pi-hole ---
echo ""
echo "--- Updating Pi-hole on $DOCKER_HOST_IP ---"
if [[ -z "$DNSMASQ_CONFIG" ]]; then
    echo "No DNS records to add to Pi-hole."
else
    echo "Creating Pi-hole configuration..."
    echo "$DNSMASQ_CONFIG" > "$TEMP_CONFIG_FILE"
    
    echo "Copying config to remote host..."
    if scp $SSH_OPTS "$TEMP_CONFIG_FILE" "${SSH_USER}@${DOCKER_HOST_IP}:/tmp/${PIHOLE_CONFIG_FILE}"; then
        echo "Applying configuration to Pi-hole container..."
        ssh $SSH_OPTS "${SSH_USER}@${DOCKER_HOST_IP}" "
            # Copy to Pi-hole volume (assuming standard path or mapped volume)
            # We need to find where the volume is or use docker cp
            
            # Try to copy directly into container
            docker cp /tmp/${PIHOLE_CONFIG_FILE} ${PIHOLE_CONTAINER}:/etc/dnsmasq.d/${PIHOLE_CONFIG_FILE} && \
            
            # Restart DNS resolver
            echo 'Restarting Pi-hole DNS...' && \
            docker exec ${PIHOLE_CONTAINER} pihole reloaddns && \
            
            # Clean up
            rm /tmp/${PIHOLE_CONFIG_FILE}
        "
        if [[ $? -eq 0 ]]; then
             echo "Pi-hole updated successfully!"
        else
             echo "Failed to update Pi-hole container."
        fi
    else
        echo "Failed to copy config to remote host. Check SSH connectivity."
    fi
    
    # Clean up local temp file
    rm "$TEMP_CONFIG_FILE"
fi


