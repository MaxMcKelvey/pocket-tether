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

# Check if WireGuard is available
check_wg() {
    if ! command -v wg &> /dev/null; then
        log_error "WireGuard (wg) command not found. Please install WireGuard."
        return 1
    fi
    return 0
}

# Check if SSH is available
check_ssh() {
    if ! command -v ssh &> /dev/null; then
        log_error "SSH not found. Please install OpenSSH client."
        return 1
    fi
    return 0
}

# Initialize WireGuard interface
wg_up() {
    if ! check_wg; then
        return 1
    fi

    if [ ! -f "$WG_CONFIG" ]; then
        log_error "WireGuard config not found at $WG_CONFIG"
        log_info "Please copy your WireGuard config to $WG_CONFIG"
        return 1
    fi

    # Check if interface is already up
    if ip link show "$WG_INTERFACE" &> /dev/null 2>&1 || ifconfig "$WG_INTERFACE" &> /dev/null 2>&1; then
        log_warn "WireGuard interface $WG_INTERFACE is already up"
        return 0
    fi

    log_info "Bringing up WireGuard interface $WG_INTERFACE..."
    
    # Try wg-quick if available (preferred method)
    if command -v wg-quick &> /dev/null; then
        sudo wg-quick up "$WG_CONFIG" 2>&1 | grep -v "Warning" || true
    else
        # Fallback to manual setup
        sudo wg setconf "$WG_INTERFACE" "$WG_CONFIG" || {
            log_error "Failed to configure WireGuard interface"
            return 1
        }
        # Bring interface up (platform-specific)
        if command -v ip &> /dev/null; then
            sudo ip link set "$WG_INTERFACE" up
        elif command -v ifconfig &> /dev/null; then
            sudo ifconfig "$WG_INTERFACE" up
        fi
    fi

    log_info "WireGuard interface $WG_INTERFACE is up"
    return 0
}

# Tear down WireGuard interface
wg_down() {
    if ! check_wg; then
        return 1
    fi

    if ! ip link show "$WG_INTERFACE" &> /dev/null 2>&1 && ! ifconfig "$WG_INTERFACE" &> /dev/null 2>&1; then
        log_warn "WireGuard interface $WG_INTERFACE is not up"
        return 0
    fi

    log_info "Bringing down WireGuard interface $WG_INTERFACE..."
    
    if command -v wg-quick &> /dev/null; then
        sudo wg-quick down "$WG_CONFIG" 2>&1 | grep -v "Warning" || true
    else
        if command -v ip &> /dev/null; then
            sudo ip link set "$WG_INTERFACE" down
        elif command -v ifconfig &> /dev/null; then
            sudo ifconfig "$WG_INTERFACE" down
        fi
        sudo wg-quick down "$WG_INTERFACE" 2>&1 | grep -v "Warning" || true
    fi

    log_info "WireGuard interface $WG_INTERFACE is down"
    return 0
}

# Check WireGuard connection status
wg_status() {
    if ! check_wg; then
        return 1
    fi

    if ip link show "$WG_INTERFACE" &> /dev/null 2>&1 || ifconfig "$WG_INTERFACE" &> /dev/null 2>&1; then
        log_info "WireGuard interface $WG_INTERFACE status:"
        wg show "$WG_INTERFACE" 2>/dev/null || log_warn "Interface exists but wg show failed"
    else
        log_warn "WireGuard interface $WG_INTERFACE is not up"
        return 1
    fi
}

# Connect to remote server via SSH with tmux
pt_connect() {
    if ! check_ssh; then
        return 1
    fi

    # Ensure WireGuard is up
    if ! wg_status &> /dev/null; then
        log_info "WireGuard not up, attempting to bring it up..."
        wg_up || {
            log_error "Failed to bring up WireGuard. Cannot connect."
            return 1
        }
        sleep 2
    fi

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
  wg_up             - Bring up WireGuard interface
  wg_down           - Bring down WireGuard interface
  wg_status         - Show WireGuard connection status
  pt_connect / pt   - Connect to remote server via SSH with tmux
  pt_help           - Show this help message

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

