#!/bin/bash

# YubiKey Verification Script
# Tests both regular SSH key and YubiKey PIV key

set -e

echo "🔐 YubiKey & SSH Key Verification"
echo "=================================="
echo ""

# Check YubiKey connection
echo "1️⃣  Checking YubiKey Connection..."
if command -v ykman &> /dev/null; then
    if ykman info &> /dev/null; then
        echo "✅ YubiKey detected!"
        ykman info | head -5
        echo ""
    else
        echo "❌ YubiKey not detected. Please plug it in."
        exit 1
    fi
else
    echo "❌ ykman not installed. Install with: brew install ykman"
    exit 1
fi

# Check PIV slot
echo "2️⃣  Checking PIV Keys..."
if ykman piv keys list &> /dev/null; then
    echo "✅ PIV module accessible"
    echo ""
    echo "PIV keys in slots:"
    ykman piv keys list 2>&1 || echo "   No keys found or error listing keys"
    echo ""
else
    echo "⚠️  Could not access PIV keys"
fi

# Verify regular SSH key
echo "3️⃣  Verifying Regular SSH Key (for Terraform)..."
if [ -f ~/.ssh/id_ed25519_homelab ]; then
    echo "✅ Private key exists: ~/.ssh/id_ed25519_homelab"
    if [ -f ~/.ssh/id_ed25519_homelab.pub ]; then
        echo "✅ Public key exists: ~/.ssh/id_ed25519_homelab.pub"
        echo ""
        echo "Public key fingerprint:"
        ssh-keygen -lf ~/.ssh/id_ed25519_homelab.pub
        echo ""
    fi
else
    echo "❌ Regular SSH key not found"
fi

# Verify PIV public key
echo "4️⃣  Verifying YubiKey PIV Public Key..."
if [ -f ~/.ssh/id_ecdsa_piv.pub ]; then
    echo "✅ PIV public key exists: ~/.ssh/id_ecdsa_piv.pub"
    echo ""
    echo "PIV public key:"
    cat ~/.ssh/id_ecdsa_piv.pub
    echo ""
    echo "Public key fingerprint:"
    ssh-keygen -lf ~/.ssh/id_ecdsa_piv.pub
    echo ""
else
    echo "⚠️  PIV public key not found (~/.ssh/id_ecdsa_piv.pub)"
fi

# Test SSH key authentication (if we have a test server)
echo "5️⃣  Testing SSH Key Authentication..."
echo ""
read -p "Do you want to test SSH connection to a server? (y/n): " test_ssh
if [ "$test_ssh" = "y" ]; then
    read -p "Enter server address (user@host): " server_address
    if [ -n "$server_address" ]; then
        echo ""
        echo "Testing regular SSH key..."
        ssh -i ~/.ssh/id_ed25519_homelab -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new $server_address "echo '✅ Regular SSH key works!'" 2>&1 || echo "❌ Connection failed or key not authorized"
        
        echo ""
        echo "To test PIV key, you'll need to:"
        echo "1. Export the public key to the server first"
        echo "2. Use PKCS11 provider: ssh -I /opt/homebrew/lib/libykcs11.dylib $server_address"
    fi
fi

# Instructions for using YubiKey PIV with SSH
echo ""
echo "📋 Using YubiKey PIV for SSH:"
echo "=============================="
echo ""
echo "To use your YubiKey PIV key for SSH:"
echo ""
echo "1. Make sure the public key is on the remote server:"
echo "   cat ~/.ssh/id_ecdsa_piv.pub | ssh user@server 'cat >> ~/.ssh/authorized_keys'"
echo ""
echo "2. Install PKCS11 provider (if needed):"
echo "   brew install opensc"
echo ""
echo "3. Connect using PKCS11:"
echo "   ssh -I /opt/homebrew/lib/libykcs11.dylib user@server"
echo ""
echo "   OR add to ~/.ssh/config:"
echo "   Host *"
echo "       PKCS11Provider /opt/homebrew/lib/libykcs11.dylib"
echo ""
echo "4. You'll be prompted for your YubiKey PIV PIN when connecting"
echo ""

echo "✅ Verification complete!"

