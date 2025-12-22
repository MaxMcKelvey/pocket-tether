#!/bin/bash
# termux-setup.sh - Termux-specific setup script for pocket-tether

# This script should be run once to set up pocket-tether in Termux

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POCKET_TETHER_DIR="$HOME/.pocket-tether"

echo "Setting up pocket-tether for Termux..."

# Check if running in Termux
if [ ! -d "$PREFIX" ] || [ -z "$PREFIX" ]; then
    echo "Warning: This doesn't appear to be a Termux environment."
    echo "Continuing anyway..."
fi

# Install required packages
echo "Installing required packages..."
pkg update -y
pkg install -y \
    wireguard-tools \
    openssh \
    tmux \
    git \
    curl \
    bash

# Create pocket-tether directory
mkdir -p "$POCKET_TETHER_DIR"

# Copy main script
cp "$SCRIPT_DIR/pocket-tether.sh" "$POCKET_TETHER_DIR/"
chmod +x "$POCKET_TETHER_DIR/pocket-tether.sh"

# Source the script in .bashrc if not already present
BASHRC="$HOME/.bashrc"
if ! grep -q "pocket-tether.sh" "$BASHRC" 2>/dev/null; then
    echo "" >> "$BASHRC"
    echo "# pocket-tether" >> "$BASHRC"
    echo "export POCKET_TETHER_DIR=\"\$HOME/.pocket-tether\"" >> "$BASHRC"
    echo "source \"\$POCKET_TETHER_DIR/pocket-tether.sh\"" >> "$BASHRC"
    echo "Added pocket-tether to $BASHRC"
else
    echo "pocket-tether already configured in $BASHRC"
fi

# Create SSH directory if it doesn't exist
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

# Generate SSH key if it doesn't exist
if [ ! -f "$HOME/.ssh/id_ed25519" ]; then
    echo "Generating SSH key..."
    ssh-keygen -t ed25519 -f "$HOME/.ssh/id_ed25519" -N "" -C "pocket-tether-termux"
    echo ""
    echo "SSH public key (add this to your server's ~/.ssh/authorized_keys):"
    cat "$HOME/.ssh/id_ed25519.pub"
    echo ""
fi

# Note about WireGuard config
echo ""
echo "Setup complete!"
echo ""
echo "Next steps:"
echo "1. Copy your WireGuard client config to: $POCKET_TETHER_DIR/wg0.conf"
echo "2. Configure server connection variables in ~/.bashrc:"
echo "   export SERVER_WG_IP='10.0.0.1'"
echo "   export SERVER_SSH_HOST='10.0.0.1'"
echo "   export SERVER_SSH_USER='your-username'"
echo "3. Restart Termux or run: source ~/.bashrc"
echo "4. Run 'pt_setup' to verify configuration"
echo "5. Run 'pt' or 'pt_connect' to connect to your server"

