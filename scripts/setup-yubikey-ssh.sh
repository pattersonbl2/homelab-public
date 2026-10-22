#!/bin/bash

# YubiKey SSH Key Setup Script
# This script helps you create SSH keys for use with YubiKey hardware tokens

set -e

echo "🔐 YubiKey SSH Key Setup"
echo "========================"
echo ""

# Check if YubiKey is connected
if command -v ykman &> /dev/null; then
    echo "🔍 Checking for YubiKey..."
    if ykman info &> /dev/null; then
        echo "✅ YubiKey detected!"
        YUBIKEY_DETECTED=true
    else
        echo "⚠️  YubiKey not detected, but continuing with key generation..."
        YUBIKEY_DETECTED=false
    fi
else
    echo "⚠️  ykman not installed. Install it with: brew install ykman"
    echo "   Continuing with key generation..."
    YUBIKEY_DETECTED=false
fi

echo ""
echo "Select YubiKey SSH setup method:"
echo "1) FIDO2/WebAuthn (Recommended - Modern, simpler)"
echo "2) PIV (Personal Identity Verification - More traditional)"
echo "3) Generate regular SSH key and add to YubiKey later"
echo ""
read -p "Enter choice [1-3]: " choice

SSH_KEY_NAME=""
KEY_TYPE=""
YUBIKEY_SLOT=""

case $choice in
    1)
        echo ""
        echo "🔑 Setting up FIDO2 SSH key..."
        SSH_KEY_NAME="id_ed25519_sk"
        KEY_TYPE="ed25519-sk"
        
        if [ "$YUBIKEY_DETECTED" = true ]; then
            echo "Touch your YubiKey when prompted..."
            ssh-keygen -t ed25519-sk -C "yubikey-fido2-$(whoami)@$(hostname)" -f ~/.ssh/$SSH_KEY_NAME
            echo "✅ FIDO2 SSH key created!"
        else
            echo "⚠️  YubiKey not detected. Please connect your YubiKey and run:"
            echo "   ssh-keygen -t ed25519-sk -C \"yubikey-fido2-$(whoami)@$(hostname)\" -f ~/.ssh/$SSH_KEY_NAME"
            exit 1
        fi
        ;;
    2)
        echo ""
        echo "🔑 Setting up PIV SSH key..."
        SSH_KEY_NAME="id_ecdsa_piv"
        
        if [ "$YUBIKEY_DETECTED" = true ]; then
            echo ""
            echo "PIV slots:"
            echo "  9a = Authentication (PIN required)"
            echo "  9c = Digital Signature"
            echo "  9d = Key Management"
            echo "  9e = Card Authentication"
            read -p "Enter slot (default: 9a): " YUBIKEY_SLOT
            YUBIKEY_SLOT=${YUBIKEY_SLOT:-9a}
            
            echo "Setting up PIV on slot $YUBIKEY_SLOT..."
            ykman piv keys generate -a ECCP256 $YUBIKEY_SLOT ~/.ssh/$SSH_KEY_NAME.pub
            
            echo "Extracting public key..."
            ykman piv keys export $YUBIKEY_SLOT ~/.ssh/$SSH_KEY_NAME.pub
            
            echo "✅ PIV SSH key created on slot $YUBIKEY_SLOT!"
            echo "   Note: The private key is stored on the YubiKey, not on disk."
        else
            echo "⚠️  YubiKey not detected. Please connect your YubiKey first."
            exit 1
        fi
        ;;
    3)
        echo ""
        echo "🔑 Generating regular SSH key..."
        SSH_KEY_NAME="id_ed25519_yubikey"
        KEY_TYPE="ed25519"
        
        ssh-keygen -t ed25519 -C "yubikey-$(whoami)@$(hostname)" -f ~/.ssh/$SSH_KEY_NAME
        echo "✅ SSH key created!"
        echo ""
        echo "To add this key to YubiKey later:"
        echo "  1. For PIV: ykman piv keys import -a RSA2048 9a ~/.ssh/$SSH_KEY_NAME"
        echo "  2. Or use gpg --edit-card to import OpenPGP keys"
        ;;
    *)
        echo "❌ Invalid choice"
        exit 1
        ;;
esac

# Display public key
echo ""
echo "📋 Your public SSH key:"
echo "========================"
cat ~/.ssh/$SSH_KEY_NAME.pub
echo ""

# Add to SSH config
SSH_CONFIG="$HOME/.ssh/config"
if [ ! -f "$SSH_CONFIG" ]; then
    touch "$SSH_CONFIG"
    chmod 600 "$SSH_CONFIG"
fi

echo ""
read -p "Add key to SSH config? (y/n): " add_to_config
if [ "$add_to_config" = "y" ]; then
    echo ""
    echo "Adding configuration to ~/.ssh/config..."
    
    # Backup config
    cp "$SSH_CONFIG" "$SSH_CONFIG.backup.$(date +%Y%m%d_%H%M%S)"
    
    cat >> "$SSH_CONFIG" << EOF

# YubiKey SSH Configuration
Host *
    IdentityFile ~/.ssh/$SSH_KEY_NAME
    IdentitiesOnly yes
EOF
    
    echo "✅ Added to SSH config!"
    echo "   Backup saved to: $SSH_CONFIG.backup.*"
fi

# Instructions for adding to servers
echo ""
echo "📤 To use this key on remote servers:"
echo "======================================"
echo ""
echo "1. Copy your public key:"
echo "   cat ~/.ssh/$SSH_KEY_NAME.pub"
echo ""
echo "2. Add to remote server:"
echo "   ssh-copy-id -i ~/.ssh/$SSH_KEY_NAME.pub user@remote-server"
echo ""
echo "   Or manually add to ~/.ssh/authorized_keys on the server"
echo ""
echo "3. Test connection:"
echo "   ssh -i ~/.ssh/$SSH_KEY_NAME user@remote-server"
echo ""

# YubiKey-specific instructions
if [ "$choice" = "1" ]; then
    echo "💡 FIDO2 Notes:"
    echo "   - You'll need to touch the YubiKey when connecting"
    echo "   - Works with OpenSSH 8.2+"
    echo "   - Public key format: sk-*"
elif [ "$choice" = "2" ]; then
    echo "💡 PIV Notes:"
    echo "   - You'll be prompted for PIN when connecting"
    echo "   - Private key is stored on YubiKey (more secure)"
    echo "   - Set PIN with: ykman piv change-pin"
    echo "   - Set PUK with: ykman piv change-puk"
fi

echo ""
echo "✅ Setup complete!"

