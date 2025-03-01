#!/bin/bash

# Ensure the script is run as root
if [[ $EUID -ne 0 ]]; then
  echo "[-] This script must be run as root or with sudo."
  exit 1
fi

# Prompt for the username
read -p "Enter the username: " USER
if [ -z "$USER" ]; then
  echo "[-] Username cannot be empty."
  exit 1
fi

# Ensure the user exists
if ! id "$USER" &>/dev/null; then
  echo "[-] User '$USER' does not exist."
  exit 1
fi

# Prompt for the remote host (optional)
read -p "Enter the remote host (leave blank if not needed): " REMOTE_HOST

# Define key paths
SSH_DIR="/home/$USER/.ssh"
KEY_PATH="$SSH_DIR/id_rsa"

# Create .ssh directory if it doesn't exist
sudo -u "$USER" mkdir -p "$SSH_DIR"

# Generate SSH key if it does not exist
if [ ! -f "$KEY_PATH" ]; then
  echo "[+] Generating RSA SSH key for $USER..."
  sudo -u "$USER" ssh-keygen -t rsa -b 4096 -N "" -f "$KEY_PATH"
else
  echo "[!] SSH key already exists for $USER at $KEY_PATH"
fi

# Set correct permissions
chmod 700 "$SSH_DIR"
chmod 600 "$KEY_PATH"
chmod 644 "$KEY_PATH.pub"

# Restrict private key access (requires sudo)
chown root:root "$KEY_PATH"
chmod 400 "$KEY_PATH"

# Ensure authorized_keys file exists and add the public key
AUTHORIZED_KEYS="$SSH_DIR/authorized_keys"
if ! grep -q -F "$(cat "$KEY_PATH.pub")" "$AUTHORIZED_KEYS" 2>/dev/null; then
  echo "[+] Adding public key to authorized_keys..."
  cat "$KEY_PATH.pub" >> "$AUTHORIZED_KEYS"
fi

chmod 600 "$AUTHORIZED_KEYS"

# If remote host is specified, copy the public key
if [ -n "$REMOTE_HOST" ]; then
  echo "[+] Copying public key to $REMOTE_HOST..."
  sudo -u "$USER" ssh-copy-id -i "$KEY_PATH.pub" "$USER@$REMOTE_HOST"
fi

# Display the public key
echo "[✔] SSH key setup complete!"
echo "[+] Public Key for $USER:"
cat "$KEY_PATH.pub"
