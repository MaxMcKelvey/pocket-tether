#!/bin/bash
# unix-setup.sh - Generic Unix setup script for pocket-tether
# Works on macOS, Linux, and other Unix-like systems

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POCKET_TETHER_DIR="$HOME/.pocket-tether"
OS="$(uname -s)"

echo "Setting up pocket-tether for $OS..."

# Detect package manager
if command -v brew &> /dev/null; then
    PKG_MANAGER="brew"
elif command -v apt-get &> /dev/null; then
    PKG_MANAGER="apt"
elif command -v yum &> /dev/null; then
    PKG_MANAGER="yum"
elif command -v pacman &> /dev/null; then
    PKG_MANAGER="pacman"
else
    PKG_MANAGER="unknown"
fi

# Install required packages
echo "Installing required packages using $PKG_MANAGER..."

case "$PKG_MANAGER" in
    brew)
        brew install wireguard-tools openssh tmux git curl
        ;;
    apt)
        sudo apt-get update
        sudo apt-get install -y wireguard openssh-client tmux git curl
        ;;
    yum)
        sudo yum install -y wireguard-tools openssh-clients tmux git curl
        ;;
    pacman)
        sudo pacman -S --noconfirm wireguard-tools openssh tmux git curl
        ;;
    *)
        echo "Warning: Unknown package manager. Please install manually:"
        echo "  - wireguard-tools (or wireguard)"
        echo "  - openssh-client (or openssh)"
        echo "  - tmux"
        echo "  - git"
        echo "  - curl"
        ;;
esac

# Create pocket-tether directory
mkdir -p "$POCKET_TETHER_DIR"

# Copy main script
cp "$SCRIPT_DIR/pocket-tether.sh" "$POCKET_TETHER_DIR/"
chmod +x "$POCKET_TETHER_DIR/pocket-tether.sh"

# Determine shell rc file
if [ -n "$ZSH_VERSION" ]; then
    SHELL_RC="$HOME/.zshrc"
elif [ -n "$BASH_VERSION" ]; then
    SHELL_RC="$HOME/.bashrc"
    # macOS uses .bash_profile instead of .bashrc
    if [ "$OS" = "Darwin" ] && [ ! -f "$HOME/.bashrc" ]; then
        SHELL_RC="$HOME/.bash_profile"
    fi
else
    SHELL_RC="$HOME/.profile"
fi

# Source the script in shell rc if not already present
if ! grep -q "pocket-tether.sh" "$SHELL_RC" 2>/dev/null; then
    echo "" >> "$SHELL_RC"
    echo "# pocket-tether" >> "$SHELL_RC"
    echo "export POCKET_TETHER_DIR=\"\$HOME/.pocket-tether\"" >> "$SHELL_RC"
    echo "source \"\$POCKET_TETHER_DIR/pocket-tether.sh\"" >> "$SHELL_RC"
    echo "Added pocket-tether to $SHELL_RC"
else
    echo "pocket-tether already configured in $SHELL_RC"
fi

# Create SSH directory if it doesn't exist
mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

# Generate SSH key if it doesn't exist
if [ ! -f "$HOME/.ssh/id_ed25519" ] && [ ! -f "$HOME/.ssh/id_rsa" ]; then
    echo "Generating SSH key..."
    ssh-keygen -t ed25519 -f "$HOME/.ssh/id_ed25519" -N "" -C "pocket-tether-$(hostname)"
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
echo "2. Configure server connection variables in $SHELL_RC:"
echo "   export SERVER_WG_IP='10.0.0.1'"
echo "   export SERVER_SSH_HOST='10.0.0.1'"
echo "   export SERVER_SSH_USER='your-username'"
echo "3. Restart your shell or run: source $SHELL_RC"
echo "4. Run 'pt_setup' to verify configuration"
echo "5. Run 'pt' or 'pt_connect' to connect to your server"

