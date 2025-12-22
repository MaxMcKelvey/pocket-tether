#!/bin/bash
# ssh-setup.sh - OpenSSH server setup for macOS

set -e

SSH_CONFIG="/etc/ssh/sshd_config"
SSH_CONFIG_BACKUP="/etc/ssh/sshd_config.backup.$(date +%Y%m%d_%H%M%S)"

echo "Setting up OpenSSH server on macOS..."

# Check for root
if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root (use sudo)"
    exit 1
fi

# Backup existing config
if [ -f "$SSH_CONFIG" ]; then
    cp "$SSH_CONFIG" "$SSH_CONFIG_BACKUP"
    echo "Backed up existing SSH config to $SSH_CONFIG_BACKUP"
fi

# Enable SSH service
echo "Enabling SSH service..."
sudo systemsetup -setremotelogin on || launchctl load -w /System/Library/LaunchDaemons/ssh.plist

# Configure SSH for better security and mobile connectivity
# Note: macOS uses a different sshd_config location, so we'll create a custom one
# or modify the existing one if possible

cat >> "$SSH_CONFIG" << 'EOF'

# pocket-tether optimizations
# These settings improve reliability for mobile connections

# Keep connections alive for mobile networks
ClientAliveInterval 60
ClientAliveCountMax 3

# Allow connections from WireGuard interface
# ListenAddress 10.0.0.1

# Security settings
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys

# Performance for mobile connections
TCPKeepAlive yes
Compression yes

# Allow port forwarding for development
AllowTcpForwarding yes
GatewayPorts no
EOF

echo ""
echo "SSH server configuration updated!"
echo ""
echo "Important: Make sure to:"
echo "1. Add your client's SSH public key to ~/.ssh/authorized_keys"
echo "2. Review the SSH config at $SSH_CONFIG"
echo "3. Restart SSH service: sudo launchctl unload /System/Library/LaunchDaemons/ssh.plist && sudo launchctl load /System/Library/LaunchDaemons/ssh.plist"
echo ""
echo "To test SSH connection:"
echo "  ssh -p 22 your-username@10.0.0.1"

