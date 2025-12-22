#!/bin/bash
# ssh-setup.sh - OpenSSH server setup for Linux

set -e

SSH_CONFIG="/etc/ssh/sshd_config"
SSH_CONFIG_BACKUP="/etc/ssh/sshd_config.backup.$(date +%Y%m%d_%H%M%S)"

echo "Setting up OpenSSH server on Linux..."

# Check for root
if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root (use sudo)"
    exit 1
fi

# Detect distribution
if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO=$ID
else
    DISTRO="unknown"
fi

# Install OpenSSH server if not present
if ! command -v sshd &> /dev/null; then
    echo "Installing OpenSSH server for $DISTRO..."
    case "$DISTRO" in
        ubuntu|debian)
            apt-get update
            apt-get install -y openssh-server
            ;;
        fedora|rhel|centos)
            dnf install -y openssh-server || yum install -y openssh-server
            ;;
        arch|manjaro)
            pacman -S --noconfirm openssh
            ;;
        *)
            echo "Please install OpenSSH server manually"
            ;;
    esac
fi

# Backup existing config
if [ -f "$SSH_CONFIG" ]; then
    cp "$SSH_CONFIG" "$SSH_CONFIG_BACKUP"
    echo "Backed up existing SSH config to $SSH_CONFIG_BACKUP"
fi

# Configure SSH for better security and mobile connectivity
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

# Enable and start SSH service
if command -v systemctl &> /dev/null; then
    systemctl enable sshd
    systemctl restart sshd
    echo "SSH service enabled and started"
else
    service ssh restart || /etc/init.d/ssh restart
    echo "SSH service restarted"
fi

echo ""
echo "SSH server configuration updated!"
echo ""
echo "Important: Make sure to:"
echo "1. Add your client's SSH public key to ~/.ssh/authorized_keys"
echo "2. Review the SSH config at $SSH_CONFIG"
echo "3. Test SSH connection: ssh -p 22 your-username@10.0.0.1"
echo ""
echo "To check SSH status:"
echo "  sudo systemctl status sshd"

