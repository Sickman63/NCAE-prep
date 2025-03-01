#!/bin/bash

# SSH configuration file
CONFIG_FILE="/etc/ssh/sshd_config"
BACKUP_FILE="/etc/ssh/sshd_config.bak$(date +%Y%m%d_%H%M%S)"

# Check if script is run as root
if [[ $EUID -ne 0 ]]; then
    echo "[!] This script must be run as root. Use sudo."
    exit 1
fi

# Check if SSH server is installed
if ! command -v sshd >/dev/null 2>&1 && ! command -v ssh >/dev/null 2>&1; then
    echo "[!] OpenSSH server not found. Attempting to install..."
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update && apt-get install -y openssh-server || {
            echo "[!] Failed to install openssh-server. Please install it manually."
            exit 1
        }
    elif command -v yum >/dev/null 2>&1; then
        yum install -y openssh-server || {
            echo "[!] Failed to install openssh-server. Please install it manually."
            exit 1
        }
    else
        echo "[!] Package manager not recognized. Install openssh-server manually."
        exit 1
    fi
fi

# Prompt for username with validation
while true; do
    read -rp "Enter the username for SSH key setup: " SSH_USER
    if id "$SSH_USER" >/dev/null 2>&1; then
        break
    else
        echo "[!] User $SSH_USER does not exist. Please try again."
    fi
done

USER_HOME=$(getent passwd "$SSH_USER" | cut -d: -f6)

# Prompt for key path with default suggestion
DEFAULT_KEY_PATH="$USER_HOME/.ssh/id_rsa"
echo "[i] Default SSH key path is: $DEFAULT_KEY_PATH"
read -rp "Enter the full path for the SSH key (press Enter for default): " KEY_PATH
KEY_PATH=${KEY_PATH:-$DEFAULT_KEY_PATH}

# Extract directory from key path
KEY_DIR=$(dirname "$KEY_PATH")

# Check if config file exists
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "[!] SSH configuration file $CONFIG_FILE not found. Creating a basic one..."
    echo "Port 2222" > "$CONFIG_FILE" || {
        echo "[!] Failed to create $CONFIG_FILE."
        exit 1
    }
fi

echo "[+] Backing up current SSH configuration to $BACKUP_FILE..."
cp "$CONFIG_FILE" "$BACKUP_FILE" || {
    echo "[!] Failed to create backup. Check permissions or disk space."
    exit 1
}

# Apply security settings (ensure PasswordAuthentication is last)
echo "[+] Applying security configurations..."
sed -i '/^#\?PermitRootLogin/d' "$CONFIG_FILE"
sed -i '/^#\?Protocol/d' "$CONFIG_FILE"
sed -i '/^#\?UsePrivilegeSeparation/d' "$CONFIG_FILE"
sed -i '/^#\?PermitEmptyPasswords/d' "$CONFIG_FILE"
sed -i '/^#\?X11Forwarding/d' "$CONFIG_FILE"
sed -i '/^#\?TCPKeepAlive/d' "$CONFIG_FILE"
sed -i '/^#\?Port/d' "$CONFIG_FILE"
sed -i '/^#\?PubkeyAuthentication/d' "$CONFIG_FILE"
sed -i '/^#\?PasswordAuthentication/d' "$CONFIG_FILE"

# Append settings explicitly to ensure order
{
    echo "PermitRootLogin no"
    echo "Protocol 2"
    echo "PermitEmptyPasswords no"
    echo "X11Forwarding no"
    echo "TCPKeepAlive yes"
    echo "Port 2222"
    echo "PubkeyAuthentication yes"
    echo "PasswordAuthentication no"  # Last to override any earlier settings
} >> "$CONFIG_FILE"

# Ensure SSH directory exists (for authorized_keys)
SSH_DIR="$USER_HOME/.ssh"
AUTH_KEYS="$SSH_DIR/authorized_keys"

if [[ ! -d "$SSH_DIR" ]]; then
    echo "[+] Creating SSH directory for authorized_keys at $SSH_DIR..."
    mkdir -p "$SSH_DIR" || {
        echo "[!] Failed to create $SSH_DIR. Check permissions."
        exit 1
    }
    chown "$SSH_USER:$SSH_USER" "$SSH_DIR"
    chmod 700 "$SSH_DIR"
fi

# Create key directory if it doesn’t exist
if [[ ! -d "$KEY_DIR" ]]; then
    echo "[+] Creating directory for SSH key at $KEY_DIR..."
    mkdir -p "$KEY_DIR" || {
        echo "[!] Failed to create $KEY_DIR. Check permissions."
        exit 1
    }
    chown "$SSH_USER:$SSH_USER" "$KEY_DIR"
    chmod 700 "$KEY_DIR"
fi

# Generate SSH key if it doesn't exist at the specified path
if [[ ! -f "$KEY_PATH" ]]; then
    echo "[+] Generating SSH key at $KEY_PATH for $SSH_USER..."
    echo -e "\n" | sudo -u "$SSH_USER" ssh-keygen -t ed25519 -f "$KEY_PATH" -N "" -q || {
        echo "[!] Failed to generate SSH key."
        exit 1
    }
fi

# Add public key to authorized_keys (if not already present)
PUBLIC_KEY_PATH="${KEY_PATH}.pub"
if [[ -f "$PUBLIC_KEY_PATH" ]] && ! grep -qF "$(cat "$PUBLIC_KEY_PATH")" "$AUTH_KEYS" 2>/dev/null; then
    echo "[+] Adding public key to $AUTH_KEYS..."
    cat "$PUBLIC_KEY_PATH" >> "$AUTH_KEYS" || {
        echo "[!] Failed to update authorized_keys."
        exit 1
    }
fi

# Set correct permissions for authorized_keys
if [[ -f "$AUTH_KEYS" ]]; then
    chown "$SSH_USER:$SSH_USER" "$AUTH_KEYS"
    chmod 600 "$AUTH_KEYS"
fi

# Ensure privilege separation directory exists (for older systems)
PRIVSEP_DIR="/run/sshd"
if [[ ! -d "$PRIVSEP_DIR" ]]; then
    echo "[+] Creating privilege separation directory..."
    mkdir -p "$PRIVSEP_DIR" || {
        echo "[!] Failed to create $PRIVSEP_DIR."
        exit 1
    }
    chown root:root "$PRIVSEP_DIR"
    chmod 755 "$PRIVSEP_DIR"
fi

# Test SSH config before restarting
if sshd -t -f "$CONFIG_FILE" >/dev/null 2>&1; then
    # Detect and restart the correct SSH service
    echo "[+] Restarting SSH service..."
    if systemctl list-units --full -all | grep -q "sshd.service"; then
        SSH_SERVICE="sshd"
        systemctl restart sshd || {
            echo "[!] Failed to restart sshd service."
            exit 1
        }
    elif systemctl list-units --full -all | grep -q "ssh.service"; then
        SSH_SERVICE="ssh"
        systemctl restart ssh || {
            echo "[!] Failed to restart ssh service."
            exit 1
        }
    else
        # Fallback for non-systemd or manual check
        if command -v service >/dev/null 2>&1 && service ssh status >/dev/null 2>&1; then
            SSH_SERVICE="ssh"
            service ssh restart || {
                echo "[!] Failed to restart ssh service."
                exit 1
            }
        else
            echo "[!] No SSH service found (ssh or sshd). Please install or start it manually."
            echo "[i] Try: apt-get install openssh-server  or  systemctl enable sshd"
            exit 1
        fi
    fi
else
    echo "[!] SSH configuration test failed. Reverting changes..."
    cp "$BACKUP_FILE" "$CONFIG_FILE"
    exit 1
fi

# Verify PasswordAuthentication is disabled
if grep -q "^PasswordAuthentication yes" "$CONFIG_FILE"; then
    echo "[!] WARNING: PasswordAuthentication is still enabled in $CONFIG_FILE. Fixing..."
    sed -i '/^PasswordAuthentication/d' "$CONFIG_FILE"
    echo "PasswordAuthentication no" >> "$CONFIG_FILE"
    systemctl restart "$SSH_SERVICE" || service "$SSH_SERVICE" restart
fi

# Confirm changes
echo "[✔] SSH hardening complete!"
echo "[i] New SSH Port: 2222"
echo "[i] Root login: Disabled"
echo "[i] Protocol: 2"
echo "[i] Empty passwords: Disabled"
echo "[i] X11 Forwarding: Disabled"
echo "[i] TCPKeepAlive: Enabled"
echo "[i] Password Authentication: Disabled"
echo "[i] Public Key Authentication: Enabled"
echo "[i] SSH key has been set up for user: $SSH_USER"
echo "[i] SSH key stored at: $KEY_PATH"
echo "[i] Backup config saved as: $BACKUP_FILE"
echo "[i] SSH service restarted: $SSH_SERVICE"

# Display SSH port for verification with timeout
timeout 5 ss -tulpn | grep -E "2222" || echo "[i] Could not verify port 2222 - service might still be restarting"
