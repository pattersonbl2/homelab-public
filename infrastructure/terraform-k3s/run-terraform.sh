#!/bin/bash
# Helper script to run terraform with SSH agent configured

# Start SSH agent and load key
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519_homelab

# Verify key is loaded
echo "SSH keys loaded:"
ssh-add -L

# Run terraform with provided arguments
terraform "$@"

# Clean up (optional - comment out if you want agent to persist)
# kill $SSH_AGENT_PID
