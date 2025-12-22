#!/bin/bash
# wireguard-setup.sh - WireGuard server setup for Linux

set -e

WG_INTERFACE="wg0"
WG_DIR="/etc/wireguard"
WG_CONFIG="$WG_DIR/$WG_INTERFACE.conf"
WG_PORT="51820"

echo "Setting up WireGuard server on Linux..."

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

# Install WireGuard
echo "Installing WireGuard for $DISTRO..."
case "$DISTRO" in
    ubuntu|debian)
        apt-get update
        apt-get install -y wireguard wireguard-tools
        ;;
    fedora|rhel|centos)
        dnf install -y wireguard-tools || yum install -y wireguard-tools
        ;;
    arch|manjaro)
        pacman -S --noconfirm wireguard-tools
        ;;
    *)
        echo "Please install WireGuard manually for your distribution"
        echo "See: https://www.wireguard.com/install/"
        ;;
esac

# Create WireGuard directory
mkdir -p "$WG_DIR"

# Generate server keys if they don't exist
if [ ! -f "$WG_DIR/server_private.key" ]; then
    echo "Generating server keys..."
    wg genkey | tee "$WG_DIR/server_private.key" | wg pubkey > "$WG_DIR/server_public.key"
    chmod 600 "$WG_DIR/server_private.key"
    chmod 644 "$WG_DIR/server_public.key"
fi

SERVER_PRIVATE_KEY=$(cat "$WG_DIR/server_private.key")
SERVER_PUBLIC_KEY=$(cat "$WG_DIR/server_public.key")

# Get server IP (try to detect external IP)
EXTERNAL_IP=$(curl -s ifconfig.me || curl -s icanhazip.com || echo "YOUR_SERVER_IP")
INTERNAL_IP=$(hostname -I | awk '{print $1}')

# Get network interface (usually the default route interface)
NET_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)

# Generate server config
cat > "$WG_CONFIG" << EOF
[Interface]
Address = 10.0.0.1/24
ListenPort = $WG_PORT
PrivateKey = $SERVER_PRIVATE_KEY

# Enable IP forwarding and NAT
PostUp = iptables -A FORWARD -i $WG_INTERFACE -j ACCEPT; iptables -A FORWARD -o $WG_INTERFACE -j ACCEPT; iptables -t nat -A POSTROUTING -o $NET_INTERFACE -j MASQUERADE
PostDown = iptables -D FORWARD -i $WG_INTERFACE -j ACCEPT; iptables -D FORWARD -o $WG_INTERFACE -j ACCEPT; iptables -t nat -D POSTROUTING -o $NET_INTERFACE -j MASQUERADE

# Add client peers here using:
# [Peer]
# PublicKey = <client-public-key>
# AllowedIPs = 10.0.0.2/32
EOF

chmod 600 "$WG_CONFIG"

# Enable IP forwarding
echo "Enabling IP forwarding..."
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p

# Enable and start WireGuard service
if command -v systemctl &> /dev/null; then
    systemctl enable wg-quick@$WG_INTERFACE.service
    echo "WireGuard service enabled. Start with: systemctl start wg-quick@$WG_INTERFACE.service"
else
    echo "Note: Enable WireGuard on boot manually for your init system"
fi

echo ""
echo "WireGuard server setup complete!"
echo ""
echo "Server public key: $SERVER_PUBLIC_KEY"
echo "Server config: $WG_CONFIG"
echo ""
echo "To add a client:"
echo "1. Generate client keys: wg genkey | tee client_private.key | wg pubkey > client_public.key"
echo "2. Add peer to $WG_CONFIG:"
echo "   [Peer]"
echo "   PublicKey = <client-public-key>"
echo "   AllowedIPs = 10.0.0.X/32"
echo "3. Create client config with:"
echo "   [Interface]"
echo "   PrivateKey = <client-private-key>"
echo "   Address = 10.0.0.X/24"
echo ""
echo "   [Peer]"
echo "   PublicKey = $SERVER_PUBLIC_KEY"
echo "   Endpoint = $EXTERNAL_IP:$WG_PORT"
echo "   AllowedIPs = 10.0.0.0/24"
echo "   PersistentKeepalive = 25"
echo ""
echo "To start WireGuard:"
echo "  sudo wg-quick up $WG_INTERFACE"
echo ""
echo "To enable on boot (systemd):"
echo "  sudo systemctl enable --now wg-quick@$WG_INTERFACE.service"

