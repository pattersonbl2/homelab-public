#!/bin/bash

# Quick test script to verify YubiKey works with SSH

echo "🔐 YubiKey SSH Verification"
echo "==========================="
echo ""

# Check YubiKey
echo "1. Checking YubiKey..."
if ykman info &> /dev/null; then
    echo "   ✅ YubiKey detected"
    SERIAL=$(ykman info | grep "Serial" | awk '{print $3}')
    echo "   Serial: $SERIAL"
else
    echo "   ❌ YubiKey not found"
    exit 1
fi

echo ""
echo "2. Checking SSH keys..."

# Regular key for Terraform
if [ -f ~/.ssh/id_ed25519_homelab ]; then
    echo "   ✅ Regular SSH key: ~/.ssh/id_ed25519_homelab"
    echo "      Fingerprint: $(ssh-keygen -lf ~/.ssh/id_ed25519_homelab.pub | awk '{print $2}')"
else
    echo "   ❌ Regular SSH key not found"
fi

# PIV key
if [ -f ~/.ssh/id_ecdsa_piv.pub ]; then
    echo "   ✅ PIV public key: ~/.ssh/id_ecdsa_piv.pub (PEM format)"
    # Try to convert to OpenSSH format
    OPENSSH_KEY=$(ssh-keygen -i -f ~/.ssh/id_ecdsa_piv.pub -m PKCS8 2>/dev/null)
    if [ $? -eq 0 ]; then
        echo "      OpenSSH format: $OPENSSH_KEY"
    else
        echo "      (In PEM format, needs conversion for SSH)"
    fi
else
    echo "   ⚠️  PIV public key not found"
fi

echo ""
echo "3. Testing key access..."
echo ""

# Test regular key
echo "   Regular key test:"
if ssh-keygen -y -f ~/.ssh/id_ed25519_homelab &> /dev/null; then
    echo "      ✅ Regular key is accessible"
else
    echo "      ❌ Cannot access regular key"
fi

# Test PIV slot
echo "   PIV key test:"
if ykman piv keys export 9a &> /dev/null; then
    echo "      ✅ PIV slot 9a has a key"
    echo ""
    echo "   To use PIV key for SSH, you need:"
    echo "   1. Install opensc: brew install opensc"
    echo "   2. Export public key in OpenSSH format and add to server"
    echo "   3. Use: ssh -I /opt/homebrew/lib/libykcs11.dylib user@server"
else
    echo "      ⚠️  Cannot access PIV key in slot 9a"
    echo "      (This might require PIN or key doesn't exist)"
fi

echo ""
echo "📝 Summary:"
echo "==========="
echo ""
echo "✅ Regular SSH key (~/.ssh/id_ed25519_homelab) - Ready for Terraform"
echo "   This key works without YubiKey and is configured in terraform.tfvars"
echo ""
echo "🔐 YubiKey PIV key (~/.ssh/id_ecdsa_piv.pub) - For manual SSH with YubiKey"
echo "   Requires:"
echo "   - Public key added to remote server"
echo "   - PKCS11 provider configured"
echo "   - YubiKey plugged in and PIN entered"
echo ""
echo "To test SSH with regular key to your VM:"
echo "  ssh -i ~/.ssh/id_ed25519_homelab ubuntu@<VM_IP>"
echo ""

