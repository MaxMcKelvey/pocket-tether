# pocket-tether

A lightweight, Android-first remote development setup that uses Termux as a full Linux userland on the phone, WireGuard for secure always-on networking to a home server, and OpenSSH for encrypted remote shell access, with tmux providing persistent terminal sessions resilient to mobile connectivity changes.

## Overview

pocket-tether provides a reliable, low-maintenance solution for remote development from your phone. The client side is implemented entirely as shell scripts sourced via `.bashrc`, requiring no custom apps or background services. Configuration is version-controlled in a Git repository and can be optionally managed on GitHub using the GitHub CLI.

This approach leverages:
- Native terminal emulation (Termux on Android)
- Standard Unix tooling (WireGuard, OpenSSH, tmux)
- SSH best practices
- Persistent terminal sessions that survive connectivity changes

## Architecture

```
┌─────────────┐         WireGuard VPN          ┌─────────────┐
│   Client    │◄──────────────────────────────►│   Server    │
│  (Termux)   │                                │  (macOS/    │
│             │         SSH over VPN           │   Linux)    │
│  - WireGuard│◄──────────────────────────────►│             │
│  - OpenSSH  │                                │  - WireGuard│
│  - tmux     │                                │  - OpenSSH  │
└─────────────┘                                └─────────────┘
```

## Features

- **Always-on VPN**: WireGuard provides secure, low-latency connectivity
- **Persistent Sessions**: tmux sessions survive network interruptions
- **Zero Background Services**: Everything runs as shell scripts
- **Version Controlled**: Configuration managed in Git
- **Cross-Platform**: Works on Termux (Android), macOS, Linux, and other Unix systems

## Quick Start

### Server Setup

You have two options for setting up the server:

#### Option 1: Remote Setup from Termux (Recommended for Linux)

This method allows you to set up the Linux server remotely from your Termux client. It automatically handles SSH key setup, WireGuard installation, and configuration synchronization.

**Prerequisites**: SSH access to the server (password authentication is fine, the script will set up key-based auth)

```bash
# From Termux, after basic client setup
cd client
bash remote-setup.sh user@your-server-ip
```

This will:
1. Generate SSH key on client if needed
2. Add SSH key to server's `authorized_keys`
3. Install WireGuard on the server
4. Configure WireGuard server
5. Sync `pocket-tether.sh` script to server
6. Sync environment variables to server (`.bashrc` and `.zshrc`)
7. Update client `.bashrc` with synced values

#### Option 2: Manual Server Setup

#### macOS
```bash
cd server/macos
sudo bash setup.sh
```

#### Linux
```bash
cd server/linux
sudo bash setup.sh
```

This will:
1. Install and configure WireGuard
2. Install and configure OpenSSH
3. Generate server keys
4. Set up IP forwarding

### Client Setup

#### Termux (Android)
```bash
# Clone or copy the repository to your phone
cd client
bash termux-setup.sh
```

This will:
1. Install required packages (OpenSSH, tmux, qrencode)
2. Set up the pocket-tether scripts
3. Configure your shell rc file
4. Generate SSH keys

**Important**: Install the WireGuard Android app from Google Play Store:
- [WireGuard - Google Play](https://play.google.com/store/apps/details?id=com.wireguard.android)

**After basic setup, you can use remote setup** (see Server Setup above):
```bash
bash remote-setup.sh user@your-server-ip
```

#### Generic Unix (macOS, Linux, etc.)
```bash
cd client
bash unix-setup.sh
```

This will:
1. Install required packages (WireGuard, OpenSSH, tmux)
2. Set up the pocket-tether scripts
3. Configure your shell rc file
4. Generate SSH keys

### Configuration

1. **WireGuard Configuration**:
   - Copy your WireGuard client config to `~/.pocket-tether/wg0.conf`
   - The server setup scripts will generate server keys and provide instructions for adding clients

2. **SSH Configuration**:
   - Add your client's SSH public key to the server's `~/.ssh/authorized_keys`
   - Configure connection variables in your shell rc file:

```bash
export SERVER_WG_IP='10.0.0.1'
export SERVER_SSH_HOST='10.0.0.1'
export SERVER_SSH_USER='your-username'
export SERVER_SSH_PORT='22'
```

3. **Connect**:
   ```bash
   source ~/.bashrc  # or ~/.zshrc
   pt  # or pt_connect
   ```

## Usage

### Client Commands

After setup, the following commands are available:

- `pt_setup` - Initialize and verify pocket-tether configuration
- `wg_up` - Open WireGuard Android app (enable VPN manually in app)
- `wg_down` - Open WireGuard Android app (disable VPN manually in app)
- `wg_status` - Show WireGuard config location and status info
- `pt_connect` or `pt` - Connect to remote server via SSH with tmux
- `pt_help` - Show help message

**Note**: WireGuard is managed via the Android app, not command-line tools. Use the WireGuard app to enable/disable the VPN connection.

### Example Workflow

```bash
# 1. Generate WireGuard config (if not done already)
bash setup-wireguard-client.sh user@server-ip

# 2. Import config into WireGuard Android app (scan QR code or import file)

# 3. Enable VPN in WireGuard app (toggle switch in app)

# 4. Connect to server via SSH
pt

# Inside the SSH session, tmux will automatically attach or create a session
# Your work persists even if the connection drops

# Check WireGuard status
wg_status

# To disconnect: disable VPN in WireGuard app
```

## Configuration Variables

You can customize behavior by setting these environment variables in your shell rc file:

- `POCKET_TETHER_DIR` - Directory for pocket-tether files (default: `~/.pocket-tether`)
- `SERVER_WG_IP` - Server WireGuard IP address (default: `10.0.0.1`)
- `SERVER_SSH_HOST` - Server SSH hostname/IP (default: `SERVER_WG_IP`)
- `SERVER_SSH_PORT` - Server SSH port (default: `22`)
- `SERVER_SSH_USER` - Server SSH username (default: current user)
- `WG_INTERFACE` - WireGuard interface name (default: `wg0`)
- `WG_CONFIG` - Path to WireGuard config file (default: `~/.pocket-tether/wg0.conf`)

## Server Management

### Adding a New Client

1. **Generate client keys**:
   ```bash
   wg genkey | tee client_private.key | wg pubkey > client_public.key
   ```

2. **Add peer to server config** (macOS: `/usr/local/etc/wireguard/wg0.conf`, Linux: `/etc/wireguard/wg0.conf`):
   ```ini
   [Peer]
   PublicKey = <client-public-key>
   AllowedIPs = 10.0.0.X/32
   ```

3. **Create client config**:
   ```ini
   [Interface]
   PrivateKey = <client-private-key>
   Address = 10.0.0.X/24

   [Peer]
   PublicKey = <server-public-key>
   Endpoint = YOUR_SERVER_IP:51820
   AllowedIPs = 10.0.0.0/24
   PersistentKeepalive = 25
   ```

4. **Add client SSH public key** to `~/.ssh/authorized_keys` on the server

5. **Reload WireGuard**:
   ```bash
   sudo wg syncconf wg0 <(wg-quick strip wg0)
   ```

## GitHub Integration (Optional)

You can manage your configuration using GitHub CLI:

```bash
# Initialize repository
gh repo create pocket-tether-config --private

# Push configuration (excluding sensitive keys)
git add .
git commit -m "Initial configuration"
git push origin main
```

**Important**: Never commit WireGuard private keys or SSH private keys. The `.gitignore` file is configured to exclude these.

## Security Considerations

- **Private Keys**: Never share or commit private keys (WireGuard or SSH)
- **Firewall**: Consider configuring a firewall to restrict access
- **SSH Keys**: Use ed25519 keys (generated by default)
- **WireGuard**: Uses modern cryptography (ChaCha20Poly1305, Curve25519)
- **Network**: All traffic is encrypted through the WireGuard VPN

## WireGuard Configuration

For detailed information about WireGuard configuration and network setup requirements (static IP, port forwarding, firewall), see [WIREGUARD_SETUP_GUIDE.md](WIREGUARD_SETUP_GUIDE.md).

## Troubleshooting

### WireGuard won't start
- Check that the config file exists and has correct permissions (600)
- Verify the interface name doesn't conflict
- On Linux, ensure the kernel module is loaded: `sudo modprobe wireguard`

### SSH connection fails
- Verify WireGuard is up: `wg_status`
- Check SSH key is in server's `~/.ssh/authorized_keys`
- Test connection: `ssh -v user@10.0.0.1`

### Connection drops frequently
- Increase `ClientAliveInterval` in SSH config
- Check WireGuard `PersistentKeepalive` setting (should be 25)
- Verify server IP forwarding is enabled

## License

This project is provided as-is for personal use. Feel free to modify and adapt to your needs.

## Contributing

This is a personal project, but suggestions and improvements are welcome!

