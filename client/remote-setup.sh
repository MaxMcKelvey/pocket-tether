#!/bin/bash
# remote-setup.sh - Remote server setup from Termux client
# Usage: bash remote-setup.sh [user@]hostname

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

# Parse server connection string
if [ -z "$1" ]; then
    log_error "Usage: $0 [user@]hostname"
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

log_info "Setting up server: $SERVER_USER@$SERVER_HOST"

# Client-side paths
CLIENT_SSH_DIR="$HOME/.ssh"
CLIENT_KEY="$CLIENT_SSH_DIR/id_ed25519"
CLIENT_PUBKEY="$CLIENT_SSH_DIR/id_ed25519.pub"
POCKET_TETHER_DIR="${POCKET_TETHER_DIR:-$HOME/.pocket-tether}"

# Server-side paths (will be set via SSH)
SERVER_HOME=""
SERVER_SSH_DIR=""
SERVER_AUTH_KEYS=""
SERVER_BASHRC=""
SERVER_ZSHRC=""
SERVER_WG_DIR=""
SERVER_WG_CONFIG=""

# Track if key auth is working
KEY_AUTH_WORKING=false

# Sudo password (will be prompted if needed)
SUDO_PASSWORD=""
SUDO_PASSWORDLESS=false

# Check if passwordless sudo is available
check_sudo_access() {
    log_step "Checking sudo access..."
    
    if ssh_cmd "sudo -n true 2>/dev/null"; then
        SUDO_PASSWORDLESS=true
        log_info "Passwordless sudo is available"
        return 0
    else
        SUDO_PASSWORDLESS=false
        log_info "Passwordless sudo not available, will prompt for password"
        return 1
    fi
}

# Prompt for sudo password
get_sudo_password() {
    if [ "$SUDO_PASSWORDLESS" = "true" ]; then
        return 0
    fi
    
    if [ -z "$SUDO_PASSWORD" ]; then
        echo ""
        log_info "Sudo access is required for server setup"
        read -sp "Enter sudo password for $SERVER_USER@$SERVER_HOST: " SUDO_PASSWORD
        echo ""
        
        # Test the password
        if ! echo "$SUDO_PASSWORD" | ssh_cmd "sudo -S -v" 2>/dev/null; then
            log_error "Invalid sudo password"
            SUDO_PASSWORD=""
            return 1
        fi
        
        log_info "Sudo password verified"
    fi
}

# Function to run sudo command on server
sudo_cmd() {
    local cmd="$1"
    
    if [ "$SUDO_PASSWORDLESS" = "true" ]; then
        # Passwordless sudo
        ssh_cmd "sudo $cmd"
    else
        # Use sudo -S to read password from stdin
        get_sudo_password || return 1
        echo "$SUDO_PASSWORD" | ssh_cmd "sudo -S $cmd"
    fi
}

# Function to run command on server
ssh_cmd() {
    local cmd="$1"
    local use_password="${2:-false}"
    
    if [ "$use_password" = "true" ]; then
        # Try with password (will prompt if needed)
        ssh -o PreferredAuthentications=keyboard-interactive,password \
            -o PubkeyAuthentication=no \
            -o StrictHostKeyChecking=no \
            "$SERVER_USER@$SERVER_HOST" "$cmd"
    elif [ "$KEY_AUTH_WORKING" = "true" ]; then
        # Key auth is known to work, use it
        ssh -o StrictHostKeyChecking=no \
            -i "$CLIENT_KEY" \
            "$SERVER_USER@$SERVER_HOST" "$cmd"
    else
        # Try with key first, fall back to password
        if ssh -o BatchMode=yes -o ConnectTimeout=5 \
               -i "$CLIENT_KEY" \
               "$SERVER_USER@$SERVER_HOST" "echo" 2>/dev/null; then
            # Key auth works
            KEY_AUTH_WORKING=true
            ssh -o StrictHostKeyChecking=no \
                -i "$CLIENT_KEY" \
                "$SERVER_USER@$SERVER_HOST" "$cmd"
        else
            # Fall back to password
            ssh -o PreferredAuthentications=keyboard-interactive,password \
                -o PubkeyAuthentication=no \
                -o StrictHostKeyChecking=no \
                "$SERVER_USER@$SERVER_HOST" "$cmd"
        fi
    fi
}

# Function to copy file to server
scp_cmd() {
    local src="$1"
    local dst="$2"
    local use_password="${3:-false}"
    
    if [ "$use_password" = "true" ]; then
        scp -o PreferredAuthentications=keyboard-interactive,password \
            -o PubkeyAuthentication=no \
            -o StrictHostKeyChecking=no \
            "$src" "$SERVER_USER@$SERVER_HOST:$dst"
    else
        if ssh -o BatchMode=yes -o ConnectTimeout=5 \
               "$SERVER_USER@$SERVER_HOST" "echo" 2>/dev/null; then
            # Key auth works
            scp -o StrictHostKeyChecking=no \
                "$src" "$SERVER_USER@$SERVER_HOST:$dst"
        else
            # Fall back to password
            scp -o PreferredAuthentications=keyboard-interactive,password \
                -o PubkeyAuthentication=no \
                -o StrictHostKeyChecking=no \
                "$src" "$SERVER_USER@$SERVER_HOST:$dst"
        fi
    fi
}

# Detect if password is needed
check_ssh_access() {
    log_step "Checking SSH access..."
    
    # Try to connect with key
    if ssh -o BatchMode=yes -o ConnectTimeout=5 \
           "$SERVER_USER@$SERVER_HOST" "echo 'connected'" 2>/dev/null; then
        log_info "SSH key authentication works"
        return 0
    else
        log_warn "SSH key authentication failed, password may be required"
        return 1
    fi
}

# Get server home directory and paths
detect_server_paths() {
    log_step "Detecting server paths..."
    
    SERVER_HOME=$(ssh_cmd "echo \$HOME")
    SERVER_SSH_DIR="$SERVER_HOME/.ssh"
    SERVER_AUTH_KEYS="$SERVER_SSH_DIR/authorized_keys"
    SERVER_BASHRC="$SERVER_HOME/.bashrc"
    SERVER_ZSHRC="$SERVER_HOME/.zshrc"
    
    # Detect WireGuard config location
    if ssh_cmd "test -d /etc/wireguard" 2>/dev/null; then
        SERVER_WG_DIR="/etc/wireguard"
        SERVER_WG_CONFIG="/etc/wireguard/wg0.conf"
    elif ssh_cmd "test -d /usr/local/etc/wireguard" 2>/dev/null; then
        SERVER_WG_DIR="/usr/local/etc/wireguard"
        SERVER_WG_CONFIG="/usr/local/etc/wireguard/wg0.conf"
    else
        # Will create during setup
        if ssh_cmd "test -f /etc/os-release && grep -q Ubuntu /etc/os-release" 2>/dev/null; then
            SERVER_WG_DIR="/etc/wireguard"
        else
            SERVER_WG_DIR="/usr/local/etc/wireguard"
        fi
        SERVER_WG_CONFIG="$SERVER_WG_DIR/wg0.conf"
    fi
    
    log_info "Server home: $SERVER_HOME"
    log_info "WireGuard config: $SERVER_WG_CONFIG"
}

# Setup SSH key on client if needed
setup_client_ssh_key() {
    log_step "Setting up client SSH key..."
    
    mkdir -p "$CLIENT_SSH_DIR"
    chmod 700 "$CLIENT_SSH_DIR"
    
    if [ ! -f "$CLIENT_KEY" ]; then
        log_info "Generating SSH key on client..."
        ssh-keygen -t ed25519 -f "$CLIENT_KEY" -N "" -C "pocket-tether-$(hostname)"
        log_info "SSH key generated: $CLIENT_PUBKEY"
    else
        log_info "SSH key already exists: $CLIENT_KEY"
    fi
    
    # Ensure correct permissions on client key
    chmod 600 "$CLIENT_KEY" 2>/dev/null || true
    chmod 644 "$CLIENT_PUBKEY" 2>/dev/null || true
    
    log_info "Client SSH key ready: $CLIENT_KEY"
}

# Add SSH key to server
add_key_to_server() {
    log_step "Adding SSH key to server..."
    
    if [ ! -f "$CLIENT_PUBKEY" ]; then
        log_error "SSH public key not found: $CLIENT_PUBKEY"
        return 1
    fi
    
    local pubkey_content=$(cat "$CLIENT_PUBKEY")
    
    # Check if key already exists (using password auth since we're setting up key auth)
    log_info "Checking if key already exists on server..."
    local key_exists=$(ssh -o PreferredAuthentications=keyboard-interactive,password \
                          -o PubkeyAuthentication=no \
                          -o StrictHostKeyChecking=no \
                          "$SERVER_USER@$SERVER_HOST" \
                          "test -f '$SERVER_AUTH_KEYS' && grep -qF '${pubkey_content}' '$SERVER_AUTH_KEYS' 2>/dev/null && echo 'yes' || echo 'no'" 2>/dev/null || echo "no")
    
    if [ "$key_exists" = "yes" ]; then
        log_info "SSH key already in server's authorized_keys"
        # Verify it actually works
        if ssh -o BatchMode=yes -o ConnectTimeout=5 \
               -o IdentitiesOnly=yes \
               -i "$CLIENT_KEY" \
               "$SERVER_USER@$SERVER_HOST" "echo 'key works'" 2>/dev/null; then
            log_info "SSH key authentication verified"
            return 0
        else
            log_warn "Key exists but authentication failed, re-adding..."
        fi
    fi
    
    log_info "Adding SSH key to server's authorized_keys..."
    
    # Create .ssh directory if it doesn't exist (using password auth)
    ssh -o PreferredAuthentications=keyboard-interactive,password \
        -o PubkeyAuthentication=no \
        -o StrictHostKeyChecking=no \
        "$SERVER_USER@$SERVER_HOST" \
        "mkdir -p '$SERVER_SSH_DIR' && chmod 700 '$SERVER_SSH_DIR'" 2>/dev/null
    
    # Append key to authorized_keys and set proper permissions
    # Use a here-doc to avoid shell escaping issues
    ssh -o PreferredAuthentications=keyboard-interactive,password \
        -o PubkeyAuthentication=no \
        -o StrictHostKeyChecking=no \
        "$SERVER_USER@$SERVER_HOST" \
        "echo '$pubkey_content' >> '$SERVER_AUTH_KEYS' && chmod 600 '$SERVER_AUTH_KEYS' && chown \$(whoami) '$SERVER_AUTH_KEYS' 2>/dev/null || true" 2>/dev/null
    
    # Verify the key was added
    local verify_key=$(ssh -o PreferredAuthentications=keyboard-interactive,password \
                          -o PubkeyAuthentication=no \
                          -o StrictHostKeyChecking=no \
                          "$SERVER_USER@$SERVER_HOST" \
                          "grep -qF '${pubkey_content}' '$SERVER_AUTH_KEYS' 2>/dev/null && echo 'yes' || echo 'no'" 2>/dev/null || echo "no")
    
    if [ "$verify_key" != "yes" ]; then
        log_error "Failed to add SSH key to server"
        return 1
    fi
    
    log_info "SSH key added successfully"
    
    # Test the new key - use IdentitiesOnly to force using our key
    log_info "Testing SSH key authentication..."
    sleep 1
    
    # Try with explicit key file
    if ssh -o BatchMode=yes \
           -o ConnectTimeout=5 \
           -o IdentitiesOnly=yes \
           -i "$CLIENT_KEY" \
           -o StrictHostKeyChecking=no \
           "$SERVER_USER@$SERVER_HOST" "echo 'key works'" 2>/dev/null; then
        log_info "SSH key authentication verified successfully!"
        return 0
    else
        # Try without explicit key (should use default location)
        if ssh -o BatchMode=yes \
               -o ConnectTimeout=5 \
               -o StrictHostKeyChecking=no \
               "$SERVER_USER@$SERVER_HOST" "echo 'key works'" 2>/dev/null; then
            log_info "SSH key authentication verified successfully!"
            return 0
        else
            log_warn "SSH key added but authentication test failed"
            log_info "This might be due to:"
            log_info "  1. Server SSH config not allowing key authentication"
            log_info "  2. Key permissions issue on server"
            log_info "  3. SSH daemon needs to be restarted"
            log_info "Try manually: ssh -i $CLIENT_KEY $SERVER_USER@$SERVER_HOST"
            return 1
        fi
    fi
}

# Install WireGuard on server
install_wireguard_server() {
    log_step "Installing WireGuard on server..."
    
    # Check if already installed
    if ssh_cmd "command -v wg >/dev/null 2>&1"; then
        log_info "WireGuard already installed"
        return 0
    fi
    
    log_info "Installing WireGuard..."
    
    # Detect OS and install using interactive sudo
    # Use ssh -t to allocate pseudo-terminal for sudo password prompt
    local ssh_opts="-t -o StrictHostKeyChecking=no"
    if [ "$KEY_AUTH_WORKING" = "true" ]; then
        ssh_opts="$ssh_opts -i $CLIENT_KEY"
    else
        ssh_opts="$ssh_opts -o PreferredAuthentications=keyboard-interactive,password -o PubkeyAuthentication=no"
    fi
    
    local install_cmd="if [ -f /etc/os-release ]; then . /etc/os-release; \
        if [ \"\$ID\" = 'ubuntu' ] || [ \"\$ID\" = 'debian' ]; then \
            sudo apt-get update && sudo apt-get install -y wireguard wireguard-tools; \
        elif [ \"\$ID\" = 'fedora' ] || [ \"\$ID\" = 'rhel' ] || [ \"\$ID\" = 'centos' ]; then \
            sudo dnf install -y wireguard-tools 2>/dev/null || sudo yum install -y wireguard-tools; \
        elif [ \"\$ID\" = 'arch' ] || [ \"\$ID\" = 'manjaro' ]; then \
            sudo pacman -S --noconfirm wireguard-tools; \
        else \
            echo 'Please install WireGuard manually for your distribution'; \
        fi; \
    else \
        echo 'Cannot detect OS, please install WireGuard manually'; \
    fi"
    
    ssh $ssh_opts "$SERVER_USER@$SERVER_HOST" "$install_cmd"
    
    # Verify installation
    if ssh_cmd "command -v wg >/dev/null 2>&1"; then
        log_info "WireGuard installed successfully"
    else
        log_error "WireGuard installation may have failed"
        return 1
    fi
}

# Setup WireGuard on server
setup_wireguard_server() {
    log_step "Setting up WireGuard server configuration..."
    
    local wg_interface="wg0"
    local wg_port="51820"
    
    # Helper function for interactive sudo commands
    local ssh_sudo_opts="-t -o StrictHostKeyChecking=no"
    if [ "$KEY_AUTH_WORKING" = "true" ]; then
        ssh_sudo_opts="$ssh_sudo_opts -i $CLIENT_KEY"
    else
        ssh_sudo_opts="$ssh_sudo_opts -o PreferredAuthentications=keyboard-interactive,password -o PubkeyAuthentication=no"
    fi
    
    # Check if config already exists
    if ssh $ssh_sudo_opts "$SERVER_USER@$SERVER_HOST" "sudo test -f '$SERVER_WG_CONFIG'" 2>/dev/null; then
        log_warn "WireGuard config already exists at $SERVER_WG_CONFIG"
        log_info "Skipping WireGuard server setup (already configured)"
        return 0
    fi
    
    log_info "Creating WireGuard server configuration..."
    
    # Create WireGuard directory
    ssh $ssh_sudo_opts "$SERVER_USER@$SERVER_HOST" "sudo mkdir -p '$SERVER_WG_DIR'"
    
    # Generate server keys
    log_info "Generating server keys..."
    local server_private=$(ssh_cmd "wg genkey")
    local server_public=$(ssh_cmd "echo '$server_private' | wg pubkey")
    
    # Save private key on server
    ssh $ssh_sudo_opts "$SERVER_USER@$SERVER_HOST" \
        "echo '$server_private' | sudo tee '$SERVER_WG_DIR/server_private.key' > /dev/null && \
         sudo chmod 600 '$SERVER_WG_DIR/server_private.key'"
    
    # Save public key on server
    ssh $ssh_sudo_opts "$SERVER_USER@$SERVER_HOST" \
        "echo '$server_public' | sudo tee '$SERVER_WG_DIR/server_public.key' > /dev/null && \
         sudo chmod 644 '$SERVER_WG_DIR/server_public.key'"
    
    # Get server external IP (try multiple methods)
    local external_ip=$(ssh_cmd "curl -s --max-time 5 ifconfig.me 2>/dev/null || \
                                  curl -s --max-time 5 icanhazip.com 2>/dev/null || \
                                  curl -s --max-time 5 ipinfo.io/ip 2>/dev/null || \
                                  echo 'YOUR_SERVER_IP'")
    
    # Get network interface for NAT
    local net_interface=$(ssh_cmd "ip route | grep default | awk '{print \$5}' | head -n1 || echo 'eth0'")
    
    # Create WireGuard config
    local wg_config_content="[Interface]
Address = 10.0.0.1/24
ListenPort = $wg_port
PrivateKey = $server_private

# Enable IP forwarding and NAT
PostUp = iptables -A FORWARD -i $wg_interface -j ACCEPT; iptables -A FORWARD -o $wg_interface -j ACCEPT; iptables -t nat -A POSTROUTING -o $net_interface -j MASQUERADE
PostDown = iptables -D FORWARD -i $wg_interface -j ACCEPT; iptables -D FORWARD -o $wg_interface -j ACCEPT; iptables -t nat -D POSTROUTING -o $net_interface -j MASQUERADE

# Add client peers here using:
# [Peer]
# PublicKey = <client-public-key>
# AllowedIPs = 10.0.0.2/32
"
    
    # Write config to temp file and copy to server
    local temp_config=$(mktemp)
    echo "$wg_config_content" > "$temp_config"
    scp_cmd "$temp_config" "/tmp/wg0.conf"
    rm "$temp_config"
    
    # Move to final location with sudo
    ssh $ssh_sudo_opts "$SERVER_USER@$SERVER_HOST" \
        "sudo mv /tmp/wg0.conf '$SERVER_WG_CONFIG' && sudo chmod 600 '$SERVER_WG_CONFIG'"
    
    # Enable IP forwarding
    log_info "Enabling IP forwarding..."
    ssh $ssh_sudo_opts "$SERVER_USER@$SERVER_HOST" \
        "echo 'net.ipv4.ip_forward=1' | sudo tee -a /etc/sysctl.conf > /dev/null && \
         sudo sysctl -p > /dev/null 2>&1 || true"
    
    log_info "WireGuard server configured"
    log_info "Server public key: $server_public"
    log_info "Server external IP: $external_ip"
    log_info "WireGuard config: $SERVER_WG_CONFIG"
}

# Sync environment variables from client to server
sync_env_vars() {
    log_step "Syncing environment variables to server..."
    
    # Read current client env vars (from .bashrc or environment)
    local client_bashrc="$HOME/.bashrc"
    local env_vars=()
    
    # Extract pocket-tether env vars from client .bashrc if they exist
    if [ -f "$client_bashrc" ]; then
        while IFS= read -r line; do
            if [[ "$line" =~ ^export\ (SERVER_|POCKET_TETHER_|WG_) ]]; then
                env_vars+=("$line")
            fi
        done < "$client_bashrc"
    fi
    
    # Also check current environment
    for var in SERVER_WG_IP SERVER_SSH_HOST SERVER_SSH_PORT SERVER_SSH_USER \
               POCKET_TETHER_DIR WG_INTERFACE WG_CONFIG; do
        if [ -n "${!var}" ]; then
            env_vars+=("export $var='${!var}'")
        fi
    done
    
    # Default values if not set
    local default_vars=(
        "export POCKET_TETHER_DIR=\"\$HOME/.pocket-tether\""
        "export SERVER_WG_IP=\"10.0.0.1\""
        "export SERVER_SSH_HOST=\"10.0.0.1\""
        "export SERVER_SSH_PORT=\"22\""
        "export SERVER_SSH_USER=\"$SERVER_USER\""
        "export WG_INTERFACE=\"wg0\""
        "export WG_CONFIG=\"\$POCKET_TETHER_DIR/wg0.conf\""
    )
    
    # Merge defaults with found vars (found vars take precedence)
    local all_vars=("${default_vars[@]}")
    for var in "${env_vars[@]}"; do
        local var_name=$(echo "$var" | sed -n 's/export \([^=]*\)=.*/\1/p')
        # Remove old entry and add new one
        all_vars=("${all_vars[@]//export $var_name=*/}")
        all_vars+=("$var")
    done
    
    # Add pocket-tether source line
    local source_line="source \"\$POCKET_TETHER_DIR/pocket-tether.sh\""
    
    # Update server .bashrc
    log_info "Updating server .bashrc..."
    ssh_cmd "mkdir -p '$SERVER_HOME'"
    
    # Remove old pocket-tether section if exists
    ssh_cmd "sed -i '/# pocket-tether/,/# end pocket-tether/d' '$SERVER_BASHRC' 2>/dev/null || true"
    
    # Add new section
    {
        echo ""
        echo "# pocket-tether"
        printf '%s\n' "${all_vars[@]}"
        echo "$source_line"
        echo "# end pocket-tether"
    } | ssh_cmd "cat >> '$SERVER_BASHRC'"
    
    # Update server .zshrc (if zsh is installed)
    if ssh_cmd "command -v zsh >/dev/null 2>&1"; then
        log_info "Updating server .zshrc..."
        ssh_cmd "touch '$SERVER_ZSHRC'"
        
        # Remove old pocket-tether section if exists
        ssh_cmd "sed -i '/# pocket-tether/,/# end pocket-tether/d' '$SERVER_ZSHRC' 2>/dev/null || true"
        
        # Add new section
        {
            echo ""
            echo "# pocket-tether"
            printf '%s\n' "${all_vars[@]}"
            echo "$source_line"
            echo "# end pocket-tether"
        } | ssh_cmd "cat >> '$SERVER_ZSHRC'"
    else
        log_info "zsh not installed on server, skipping .zshrc update"
    fi
    
    log_info "Environment variables synced to server"
}

# Copy pocket-tether.sh to server
sync_pocket_tether_script() {
    log_step "Syncing pocket-tether script to server..."
    
    local script_path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/pocket-tether.sh"
    
    if [ ! -f "$script_path" ]; then
        log_error "pocket-tether.sh not found at $script_path"
        return 1
    fi
    
    # Create server pocket-tether directory
    ssh_cmd "mkdir -p '\$HOME/.pocket-tether'"
    
    # Copy script
    scp_cmd "$script_path" "\$HOME/.pocket-tether/pocket-tether.sh"
    ssh_cmd "chmod +x '\$HOME/.pocket-tether/pocket-tether.sh'"
    
    log_info "pocket-tether.sh synced to server"
}

# Update client .bashrc with synced values
update_client_bashrc() {
    log_step "Updating client .bashrc with synced values..."
    
    local client_bashrc="$HOME/.bashrc"
    touch "$client_bashrc"
    
    # Remove old pocket-tether section if exists
    sed -i.bak '/# pocket-tether/,/# end pocket-tether/d' "$client_bashrc" 2>/dev/null || true
    
    # Get synced values (use defaults or existing)
    local server_wg_ip="${SERVER_WG_IP:-10.0.0.1}"
    local server_ssh_host="${SERVER_SSH_HOST:-$server_wg_ip}"
    local server_ssh_port="${SERVER_SSH_PORT:-22}"
    local server_ssh_user="${SERVER_SSH_USER:-$SERVER_USER}"
    
    # Add new section
    {
        echo ""
        echo "# pocket-tether"
        echo "export POCKET_TETHER_DIR=\"\$HOME/.pocket-tether\""
        echo "export SERVER_WG_IP=\"$server_wg_ip\""
        echo "export SERVER_SSH_HOST=\"$server_ssh_host\""
        echo "export SERVER_SSH_PORT=\"$server_ssh_port\""
        echo "export SERVER_SSH_USER=\"$server_ssh_user\""
        echo "export WG_INTERFACE=\"wg0\""
        echo "export WG_CONFIG=\"\$POCKET_TETHER_DIR/wg0.conf\""
        echo "source \"\$POCKET_TETHER_DIR/pocket-tether.sh\""
        echo "# end pocket-tether"
    } >> "$client_bashrc"
    
    log_info "Client .bashrc updated"
}

# Main setup flow
main() {
    log_info "Starting remote server setup..."
    log_info "Server: $SERVER_USER@$SERVER_HOST"
    echo ""
    
    # Check SSH access
    local needs_password=false
    if ! check_ssh_access; then
        needs_password=true
        log_warn "Password authentication will be required"
    fi
    
    # Setup client SSH key
    setup_client_ssh_key
    
    # Detect server paths
    detect_server_paths
    
    # Add key to server (will prompt for password if needed)
    if add_key_to_server; then
        KEY_AUTH_WORKING=true
        log_info "SSH key setup successful - subsequent commands will use key authentication"
    else
        log_error "SSH key setup failed. Continuing with password authentication..."
        log_info "Troubleshooting steps:"
        log_info "  1. Verify key was added: ssh $SERVER_USER@$SERVER_HOST 'cat ~/.ssh/authorized_keys'"
        log_info "  2. Check permissions: ssh $SERVER_USER@$SERVER_HOST 'ls -la ~/.ssh/'"
        log_info "  3. Test manually: ssh -i $CLIENT_KEY $SERVER_USER@$SERVER_HOST"
    fi
    
    # Verify server SSH config allows key authentication (only if we can connect)
    if [ "$KEY_AUTH_WORKING" = "true" ] || ssh_cmd "true" 2>/dev/null; then
        log_step "Verifying server SSH configuration..."
        local ssh_sudo_opts="-t -o StrictHostKeyChecking=no"
        if [ "$KEY_AUTH_WORKING" = "true" ]; then
            ssh_sudo_opts="$ssh_sudo_opts -i $CLIENT_KEY"
        else
            ssh_sudo_opts="$ssh_sudo_opts -o PreferredAuthentications=keyboard-interactive,password -o PubkeyAuthentication=no"
        fi
        
        local pubkey_auth=$(ssh $ssh_sudo_opts "$SERVER_USER@$SERVER_HOST" \
            "sudo grep -E '^PubkeyAuthentication|^#PubkeyAuthentication' /etc/ssh/sshd_config 2>/dev/null | tail -1" 2>/dev/null || echo "")
        if echo "$pubkey_auth" | grep -qE "PubkeyAuthentication\s+no"; then
            log_warn "Server SSH config has PubkeyAuthentication=no"
            log_info "Attempting to enable it (requires sudo password)..."
            ssh $ssh_sudo_opts "$SERVER_USER@$SERVER_HOST" \
                "sudo sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config && \
                 sudo systemctl restart sshd 2>/dev/null || sudo service ssh restart 2>/dev/null || true" 2>/dev/null || \
            log_warn "Could not update SSH config automatically. Please enable PubkeyAuthentication manually."
        elif [ -n "$pubkey_auth" ]; then
            log_info "Server SSH config allows key authentication: $pubkey_auth"
        fi
    fi
    
    # Install WireGuard on server
    install_wireguard_server
    
    # Setup WireGuard server
    setup_wireguard_server
    
    # Sync pocket-tether script
    sync_pocket_tether_script
    
    # Sync environment variables
    sync_env_vars
    
    # Update client .bashrc
    update_client_bashrc
    
    echo ""
    log_info "Remote setup complete!"
    echo ""
    
    # Final verification
    if [ "$KEY_AUTH_WORKING" = "true" ]; then
        log_info "✓ SSH key authentication is working"
        log_info "  You can now connect without a password using:"
        log_info "  ssh $SERVER_USER@$SERVER_HOST"
    else
        log_warn "⚠ SSH key authentication may not be working"
        log_info "  To troubleshoot, try:"
        log_info "  ssh -v -i $CLIENT_KEY $SERVER_USER@$SERVER_HOST"
        log_info "  Check server logs: sudo tail -f /var/log/auth.log"
    fi
    
    echo ""
    log_info "Next steps:"
    log_info "1. Source your .bashrc: source ~/.bashrc"
    log_info "2. Generate WireGuard client config and add peer to server"
    log_info "3. Copy client WireGuard config to: ~/.pocket-tether/wg0.conf"
    log_info "4. Connect with: pt_connect or pt"
}

# Run main function
main

