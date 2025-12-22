#!/bin/bash
# wireguard-setup.sh - WireGuard server setup for macOS

set -e

WG_INTERFACE="wg0"
WG_DIR="/usr/local/etc/wireguard"
WG_CONFIG="$WG_DIR/$WG_INTERFACE.conf"
WG_PORT="51820"

echo "Setting up WireGuard server on macOS..."

# Check for root
if [ "$EUID" -ne 0 ]; then
    echo "This script must be run as root (use sudo)"
    exit 1
fi

# Install WireGuard if not present
if ! command -v wg &> /dev/null; then
    echo "Installing WireGuard..."
    brew install wireguard-tools
fi

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
INTERNAL_IP=$(ipconfig getifaddr en0 || ipconfig getifaddr en1 || echo "10.0.0.1")

# Generate server config
cat > "$WG_CONFIG" << EOF
[Interface]
Address = 10.0.0.1/24
ListenPort = $WG_PORT
PrivateKey = $SERVER_PRIVATE_KEY

# Enable IP forwarding
# PostUp = sysctl -w net.inet.ip.forwarding=1
# PostDown = sysctl -w net.inet.ip.forwarding=0

# Add client peers here using:
# [Peer]
# PublicKey = <client-public-key>
# AllowedIPs = 10.0.0.2/32
EOF

chmod 600 "$WG_CONFIG"

# Enable IP forwarding
echo "Enabling IP forwarding..."
sysctl -w net.inet.ip.forwarding=1

# Make IP forwarding persistent
if ! grep -q "net.inet.ip.forwarding=1" /etc/sysctl.conf 2>/dev/null; then
    echo "net.inet.ip.forwarding=1" >> /etc/sysctl.conf
fi

# Create launchd plist for WireGuard
PLIST_PATH="/Library/LaunchDaemons/com.wireguard.server.plist"
cat > "$PLIST_PATH" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.wireguard.server</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/wg-quick</string>
        <string>up</string>
        <string>$WG_INTERFACE</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>
</dict>
</plist>
EOF

chmod 644 "$PLIST_PATH"

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
echo "To enable on boot:"
echo "  sudo launchctl load -w $PLIST_PATH"

