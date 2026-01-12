#!/bin/bash
# pocket-tether.sh - Main client script for pocket-tether
# This script provides functions for connecting to the remote server via WireGuard and SSH

# Configuration - should be customized per installation
POCKET_TETHER_DIR="${POCKET_TETHER_DIR:-$HOME/.pocket-tether}"
SERVER_WG_IP="${SERVER_WG_IP:-10.0.0.1}"
SERVER_SSH_HOST="${SERVER_SSH_HOST:-${SERVER_WG_IP}}"
SERVER_SSH_PORT="${SERVER_SSH_PORT:-22}"
SERVER_SSH_USER="${SERVER_SSH_USER:-$(whoami)}"
WG_INTERFACE="${WG_INTERFACE:-wg0}"
WG_CONFIG="${WG_CONFIG:-${POCKET_TETHER_DIR}/wg0.conf}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Check if WireGuard Android app is available
check_wg() {
    # Check if WireGuard app is installed (via Android package manager)
    if command -v pm &> /dev/null; then
        if pm list packages | grep -q "com.wireguard.android"; then
            return 0
        fi
    fi
    # Fallback: check if config exists (app might be installed but pm not available)
    if [ -f "$WG_CONFIG" ]; then
        log_warn "WireGuard Android app status unknown. Ensure the app is installed and config is imported."
        return 0
    fi
    log_error "WireGuard Android app not found. Please install from Google Play Store."
    log_info "Install: https://play.google.com/store/apps/details?id=com.wireguard.android"
    return 1
}

# Check if SSH is available
check_ssh() {
    if ! command -v ssh &> /dev/null; then
        log_error "SSH not found. Please install OpenSSH client."
        return 1
    fi
    return 0
}

# Open WireGuard config in Android app
wg_up() {
    if ! check_wg; then
        return 1
    fi

    if [ ! -f "$WG_CONFIG" ]; then
        log_error "WireGuard config not found at $WG_CONFIG"
        log_info "Please generate config using: bash setup-wireguard-client.sh user@server"
        return 1
    fi

    log_info "Opening WireGuard Android app..."
    log_info "Please enable the VPN connection in the WireGuard app."
    
    # Try to open the WireGuard app
    if command -v am &> /dev/null; then
        # Try to open WireGuard app
        am start -n com.wireguard.android/.ui.MainActivity 2>/dev/null || \
        log_info "Please open the WireGuard app manually and enable the connection."
    else
        log_info "Please open the WireGuard app manually:"
        log_info "1. Open WireGuard app"
        log_info "2. Import the config from: $WG_CONFIG"
        log_info "3. Enable the VPN connection"
    fi
    
    log_info "Config file location: $WG_CONFIG"
    log_info "You can import this config in the WireGuard app via:"
    log_info "  - QR code (use: qrencode -t ansiutf8 < $WG_CONFIG)"
    log_info "  - File import (copy to Downloads folder and import)"
    
    return 0
}

# Disable WireGuard VPN in Android app
wg_down() {
    if ! check_wg; then
        return 1
    fi

    log_info "Please disable the VPN connection in the WireGuard Android app."
    
    # Try to open the WireGuard app
    if command -v am &> /dev/null; then
        am start -n com.wireguard.android/.ui.MainActivity 2>/dev/null || \
        log_info "Please open the WireGuard app manually to disable the connection."
    else
        log_info "Open the WireGuard app and disable the VPN connection."
    fi
    
    return 0
}

# Check WireGuard connection status
wg_status() {
    if ! check_wg; then
        return 1
    fi

    # Check if config exists
    if [ ! -f "$WG_CONFIG" ]; then
        log_warn "WireGuard config not found at $WG_CONFIG"
        return 1
    fi

    log_info "WireGuard Android app status:"
    log_info "Config file: $WG_CONFIG"
    
    # Try to check if VPN is active via Android API
    if command -v dumpsys &> /dev/null; then
        local vpn_status=$(dumpsys connectivity | grep -i "wireguard" || echo "")
        if [ -n "$vpn_status" ]; then
            log_info "VPN appears to be active (check WireGuard app to confirm)"
        else
            log_warn "VPN status unknown. Check WireGuard app to see if connection is active."
        fi
    else
        log_info "Please check the WireGuard Android app to see connection status."
        log_info "The app will show if the VPN is connected."
    fi
    
    # Show config info
    if [ -f "$WG_CONFIG" ]; then
        log_info ""
        log_info "Config details:"
        grep -E "^Address|^Endpoint" "$WG_CONFIG" 2>/dev/null || true
    fi
}

# Connect to remote server via SSH with tmux
pt_connect() {
    if ! check_ssh; then
        return 1
    fi

    # Check if WireGuard config exists
    if [ ! -f "$WG_CONFIG" ]; then
        log_error "WireGuard config not found at $WG_CONFIG"
        log_info "Please generate config using: bash setup-wireguard-client.sh user@server"
        return 1
    fi
    
    # Warn if VPN might not be active (we can't reliably check from Termux)
    log_warn "Ensure WireGuard VPN is enabled in the Android app before connecting."
    log_info "If connection fails, check that the VPN is active in WireGuard app."

    log_info "Connecting to $SERVER_SSH_USER@$SERVER_SSH_HOST:$SERVER_SSH_PORT..."

    # Try to connect with tmux
    # If tmux session exists, attach; otherwise create new session
    ssh -p "$SERVER_SSH_PORT" "$SERVER_SSH_USER@$SERVER_SSH_HOST" \
        -o ConnectTimeout=10 \
        -o ServerAliveInterval=60 \
        -o ServerAliveCountMax=3 \
        -t "tmux new-session -A -s pocket-tether || bash"
}

# Quick connect alias (shorter command)
pt() {
    pt_connect
}

# Setup function - initializes the pocket-tether environment
pt_setup() {
    log_info "Setting up pocket-tether..."

    # Create directory structure
    mkdir -p "$POCKET_TETHER_DIR"
    log_info "Created directory: $POCKET_TETHER_DIR"

    # Check for WireGuard config
    if [ ! -f "$WG_CONFIG" ]; then
        log_warn "WireGuard config not found at $WG_CONFIG"
        log_info "Please copy your WireGuard client config to: $WG_CONFIG"
    else
        log_info "Found WireGuard config at $WG_CONFIG"
    fi

    # Check for SSH key
    if [ ! -f "$HOME/.ssh/id_ed25519" ] && [ ! -f "$HOME/.ssh/id_rsa" ]; then
        log_warn "No SSH key found. Generating one..."
        ssh-keygen -t ed25519 -f "$HOME/.ssh/id_ed25519" -N "" -C "pocket-tether-$(hostname)"
        log_info "SSH key generated. Add the public key to the server:"
        cat "$HOME/.ssh/id_ed25519.pub"
    else
        log_info "SSH key found"
    fi

    log_info "Setup complete!"
    log_info "Configure variables in your .bashrc or .zshrc:"
    log_info "  export SERVER_WG_IP='10.0.0.1'"
    log_info "  export SERVER_SSH_HOST='10.0.0.1'"
    log_info "  export SERVER_SSH_USER='your-username'"
    log_info "Then use 'pt_connect' or 'pt' to connect"
}

# Show help
pt_help() {
    cat << EOF
pocket-tether - Remote development setup commands

Commands:
  pt_setup          - Initialize pocket-tether environment
  wg_up             - Open WireGuard Android app (enable VPN manually in app)
  wg_down           - Open WireGuard Android app (disable VPN manually in app)
  wg_status         - Show WireGuard config location and status info
  pt_connect / pt   - Connect to remote server via SSH with tmux
  pt_help           - Show this help message

Note: WireGuard is managed via the Android app, not command-line tools.
      Use the WireGuard app to enable/disable the VPN connection.

Configuration (set in your shell rc file):
  POCKET_TETHER_DIR - Directory for pocket-tether files (default: ~/.pocket-tether)
  SERVER_WG_IP      - Server WireGuard IP address (default: 10.0.0.1)
  SERVER_SSH_HOST   - Server SSH hostname/IP (default: SERVER_WG_IP)
  SERVER_SSH_PORT   - Server SSH port (default: 22)
  SERVER_SSH_USER   - Server SSH username (default: current user)
  WG_INTERFACE      - WireGuard interface name (default: wg0)
  WG_CONFIG         - Path to WireGuard config file (default: ~/.pocket-tether/wg0.conf)

EOF
}

# Auto-export functions for use in shell
export -f wg_up wg_down wg_status pt_connect pt pt_setup pt_help
export -f log_info log_warn log_error check_wg check_ssh

