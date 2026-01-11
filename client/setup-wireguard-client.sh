#!/bin/bash
# setup-wireguard-client.sh - Generate WireGuard client config and add peer to server
# Usage: bash setup-wireguard-client.sh [user@]hostname [client-ip]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Parse arguments
if [ -z "$1" ]; then
    log_error "Usage: $0 [user@]hostname [client-ip]"
    log_info "  [user@]hostname - Server to connect to (SSH key auth must work)"
    log_info "  [client-ip]     - Optional client IP (default: auto-assign next available)"
    exit 1
fi

SERVER_CONN="$1"
if [[ "$SERVER_CONN" == *"@"* ]]; then
    SERVER_USER="${SERVER_CONN%%@*}"
    SERVER_HOST="${SERVER_CONN#*@}"
else
    SERVER_USER="$(whoami)"
    SERVER_HOST="$SERVER_CONN"
fi

CLIENT_IP="${2:-}"

log_info "Setting up WireGuard client for server: $SERVER_USER@$SERVER_HOST"

# Client-side paths
POCKET_TETHER_DIR="${POCKET_TETHER_DIR:-$HOME/.pocket-tether}"
CLIENT_WG_CONFIG="$POCKET_TETHER_DIR/wg0.conf"
CLIENT_KEY_DIR="$POCKET_TETHER_DIR"
CLIENT_PRIVATE_KEY="$CLIENT_KEY_DIR/client_private.key"
CLIENT_PUBLIC_KEY="$CLIENT_KEY_DIR/client_public.key"

# Server-side paths (will be detected)
SERVER_WG_DIR=""
SERVER_WG_CONFIG=""
SERVER_PUBLIC_KEY=""
SERVER_EXTERNAL_IP=""
SERVER_WG_PORT="51820"

# Function to run command on server via SSH
ssh_cmd() {
    local cmd="$1"
    ssh -o StrictHostKeyChecking=no \
        "$SERVER_USER@$SERVER_HOST" "$cmd"
}

# Function to run sudo command on server via SSH (interactive)
ssh_sudo_cmd() {
    local cmd="$1"
    ssh -t -o StrictHostKeyChecking=no \
        "$SERVER_USER@$SERVER_HOST" "sudo $cmd"
}

# Detect server WireGuard configuration
detect_server_wg_config() {
    log_step "Detecting server WireGuard configuration..."
    
    # Try common locations
    if ssh_cmd "test -f /etc/wireguard/wg0.conf" 2>/dev/null; then
        SERVER_WG_DIR="/etc/wireguard"
        SERVER_WG_CONFIG="/etc/wireguard/wg0.conf"
    elif ssh_cmd "test -f /usr/local/etc/wireguard/wg0.conf" 2>/dev/null; then
        SERVER_WG_DIR="/usr/local/etc/wireguard"
        SERVER_WG_CONFIG="/usr/local/etc/wireguard/wg0.conf"
    else
        log_error "Could not find WireGuard config on server"
        log_info "Expected locations: /etc/wireguard/wg0.conf or /usr/local/etc/wireguard/wg0.conf"
        exit 1
    fi
    
    log_info "Found server WireGuard config: $SERVER_WG_CONFIG"
    
    # Get server public key (may need sudo to read)
    if ssh_sudo_cmd "test -f $SERVER_WG_DIR/server_public.key" 2>/dev/null; then
        SERVER_PUBLIC_KEY=$(ssh_sudo_cmd "cat $SERVER_WG_DIR/server_public.key" 2>/dev/null | tr -d '\r\n')
        if [ -n "$SERVER_PUBLIC_KEY" ]; then
            log_info "Retrieved server public key"
        fi
    fi
    
    # If still empty, try to extract from config
    if [ -z "$SERVER_PUBLIC_KEY" ]; then
        log_warn "Could not read server_public.key, trying to extract from config..."
        # Extract PrivateKey from config and derive public key
        local server_private=$(ssh_sudo_cmd "grep '^PrivateKey' $SERVER_WG_CONFIG 2>/dev/null | awk '{print \$3}'" 2>/dev/null | tr -d '\r\n')
        if [ -n "$server_private" ]; then
            SERVER_PUBLIC_KEY=$(echo "$server_private" | wg pubkey 2>/dev/null || echo "")
        fi
    fi
    
    if [ -z "$SERVER_PUBLIC_KEY" ]; then
        log_error "Could not find server public key"
        log_info "Please ensure server WireGuard is set up with server_public.key file"
        log_info "Expected location: $SERVER_WG_DIR/server_public.key"
        exit 1
    fi
    
    # Get server external IP
    SERVER_EXTERNAL_IP=$(ssh_cmd "curl -s --max-time 5 ifconfig.me 2>/dev/null || \
                                   curl -s --max-time 5 icanhazip.com 2>/dev/null || \
                                   curl -s --max-time 5 ipinfo.io/ip 2>/dev/null || \
                                   hostname -I | awk '{print \$1}'" 2>/dev/null || echo "")
    
    if [ -z "$SERVER_EXTERNAL_IP" ]; then
        log_warn "Could not detect server external IP"
        read -p "Enter server external IP or hostname: " SERVER_EXTERNAL_IP
    else
        log_info "Server external IP: $SERVER_EXTERNAL_IP"
    fi
    
    # Get WireGuard port from config
    SERVER_WG_PORT=$(ssh_sudo_cmd "grep '^ListenPort' $SERVER_WG_CONFIG 2>/dev/null | awk '{print \$3}'" 2>/dev/null | tr -d '\r\n' || echo "51820")
    if [ -z "$SERVER_WG_PORT" ] || [ "$SERVER_WG_PORT" = "51820" ]; then
        SERVER_WG_PORT="51820"
    fi
    log_info "Server WireGuard port: $SERVER_WG_PORT"
}

# Generate client keys
generate_client_keys() {
    log_step "Generating client keys..."
    
    mkdir -p "$CLIENT_KEY_DIR"
    
    if [ -f "$CLIENT_PRIVATE_KEY" ]; then
        log_warn "Client private key already exists: $CLIENT_PRIVATE_KEY"
        read -p "Regenerate? (y/N): " regenerate
        if [[ "$regenerate" =~ ^[Yy]$ ]]; then
            rm -f "$CLIENT_PRIVATE_KEY" "$CLIENT_PUBLIC_KEY"
        else
            log_info "Using existing client keys"
            return 0
        fi
    fi
    
    # Generate keys
    wg genkey | tee "$CLIENT_PRIVATE_KEY" | wg pubkey > "$CLIENT_PUBLIC_KEY"
    chmod 600 "$CLIENT_PRIVATE_KEY"
    chmod 644 "$CLIENT_PUBLIC_KEY"
    
    log_info "Client keys generated:"
    log_info "  Private: $CLIENT_PRIVATE_KEY"
    log_info "  Public:  $CLIENT_PUBLIC_KEY"
}

# Determine client IP
determine_client_ip() {
    log_step "Determining client IP address..."
    
    if [ -n "$CLIENT_IP" ]; then
        log_info "Using provided client IP: $CLIENT_IP"
        return 0
    fi
    
    # Get existing peer IPs from server config
    local existing_ips=$(ssh_sudo_cmd "grep -E '^AllowedIPs' $SERVER_WG_CONFIG 2>/dev/null | \
                                        sed 's/.*AllowedIPs[[:space:]]*=[[:space:]]*//' | \
                                        sed 's/\/.*//'" 2>/dev/null | tr -d '\r' || echo "")
    
    # Find next available IP in 10.0.0.0/24 range
    local base_ip="10.0.0"
    local client_ip=""
    
    for i in {2..254}; do
        local test_ip="$base_ip.$i"
        if ! echo "$existing_ips" | grep -q "^$test_ip$"; then
            client_ip="$test_ip"
            break
        fi
    done
    
    if [ -z "$client_ip" ]; then
        log_error "Could not find available IP address in 10.0.0.0/24 range"
        read -p "Enter client IP address (e.g., 10.0.0.2): " client_ip
    fi
    
    CLIENT_IP="$client_ip"
    log_info "Assigned client IP: $CLIENT_IP"
}

# Add peer to server config
add_peer_to_server() {
    log_step "Adding client peer to server configuration..."
    
    local client_public_key=$(cat "$CLIENT_PUBLIC_KEY")
    
    # Check if peer already exists
    if ssh_sudo_cmd "grep -qF '$client_public_key' $SERVER_WG_CONFIG" 2>/dev/null; then
        log_warn "Client public key already exists in server config"
        read -p "Update peer configuration? (y/N): " update
        if [[ ! "$update" =~ ^[Yy]$ ]]; then
            log_info "Skipping server config update"
            return 0
        fi
        # Remove existing peer entry
        # Use a simple approach: find the [Peer] section containing this key and remove it
        # Copy config, remove the peer block, then replace
        ssh_sudo_cmd "awk '
            /^\[Peer\]/ { in_peer=1; peer_block=\"\" }
            in_peer { peer_block=peer_block\\$0\"\\n\" }
            /PublicKey.*$client_public_key/ { skip_peer=1 }
            /^\[Peer\]/ && in_peer && !skip_peer { print peer_block; peer_block=\"\" }
            !in_peer { print }
            END { if (in_peer && !skip_peer) print peer_block }
        ' $SERVER_WG_CONFIG > /tmp/wg0.conf.new && sudo mv /tmp/wg0.conf.new $SERVER_WG_CONFIG" 2>/dev/null || \
        log_warn "Could not automatically remove existing peer. You may need to edit $SERVER_WG_CONFIG manually."
    fi
    
    # Add peer configuration
    local peer_config="[Peer]
PublicKey = $client_public_key
AllowedIPs = $CLIENT_IP/32"
    
    log_info "Adding peer to server config..."
    echo "$peer_config" | ssh_sudo_cmd "tee -a $SERVER_WG_CONFIG > /dev/null"
    
    log_info "Peer added to server configuration"
    
    # Reload WireGuard if it's running
    if ssh_sudo_cmd "wg show wg0 >/dev/null 2>&1" 2>/dev/null; then
        log_info "Reloading WireGuard configuration..."
        # Use wg syncconf to reload without dropping connections
        ssh_sudo_cmd "wg syncconf wg0 <(wg-quick strip wg0)" 2>/dev/null || \
        log_warn "Could not reload WireGuard config. You may need to restart it manually: sudo wg-quick down wg0 && sudo wg-quick up wg0"
    else
        log_info "WireGuard is not running. Start it with: sudo wg-quick up wg0"
    fi
}

# Generate client config
generate_client_config() {
    log_step "Generating client WireGuard configuration..."
    
    local client_private_key=$(cat "$CLIENT_PRIVATE_KEY")
    
    # Create client config
    local client_config="[Interface]
PrivateKey = $client_private_key
Address = $CLIENT_IP/24

[Peer]
PublicKey = $SERVER_PUBLIC_KEY
Endpoint = $SERVER_EXTERNAL_IP:$SERVER_WG_PORT
AllowedIPs = 10.0.0.0/24
PersistentKeepalive = 25
"
    
    # Write to temp file first
    local temp_config=$(mktemp)
    echo "$client_config" > "$temp_config"
    
    # Copy to final location
    mkdir -p "$POCKET_TETHER_DIR"
    cp "$temp_config" "$CLIENT_WG_CONFIG"
    chmod 600 "$CLIENT_WG_CONFIG"
    rm "$temp_config"
    
    log_info "Client configuration written to: $CLIENT_WG_CONFIG"
}

# Main flow
main() {
    log_info "Setting up WireGuard client configuration..."
    echo ""
    
    # Detect server configuration
    detect_server_wg_config
    echo ""
    
    # Generate client keys
    generate_client_keys
    echo ""
    
    # Determine client IP
    determine_client_ip
    echo ""
    
    # Add peer to server
    add_peer_to_server
    echo ""
    
    # Generate client config
    generate_client_config
    echo ""
    
    log_info "WireGuard client setup complete!"
    echo ""
    log_info "Configuration file: $CLIENT_WG_CONFIG"
    log_info "Client IP: $CLIENT_IP"
    log_info "Server endpoint: $SERVER_EXTERNAL_IP:$SERVER_WG_PORT"
    echo ""
    log_info "Next steps:"
    log_info "1. Source your .bashrc: source ~/.bashrc"
    log_info "2. Bring up WireGuard: wg_up"
    log_info "3. Connect to server: pt_connect or pt"
}

# Run main function
main

