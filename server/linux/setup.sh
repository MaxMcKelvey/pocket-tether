#!/bin/bash
# setup.sh - Complete server setup for Linux

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Setting up pocket-tether server on Linux..."
echo ""

# Run WireGuard setup
echo "=== Setting up WireGuard ==="
bash "$SCRIPT_DIR/wireguard-setup.sh"
echo ""

# Run SSH setup
echo "=== Setting up OpenSSH ==="
bash "$SCRIPT_DIR/ssh-setup.sh"
echo ""

echo "Server setup complete!"
echo ""
echo "Next steps:"
echo "1. Start WireGuard: sudo wg-quick up wg0"
echo "2. Add client WireGuard peers to /etc/wireguard/wg0.conf"
echo "3. Add client SSH public keys to ~/.ssh/authorized_keys"
echo "4. Test connection from client"

