#!/bin/bash

# Prompt for the username
read -p "Enter the username: " USER
if [ -z "$USER" ]; then
  echo "Username cannot be empty."
  exit 1
fi

# Prompt for the remote host (optional)
read -p "Enter the remote host (leave blank if not needed): " REMOTE_HOST

KEY_PATH="/home/$USER/.ssh/id_rsa"

# Generate SSH key if not already existing
if [ ! -f "$KEY_PATH" ]; then
  echo "[+] Generating SSH key for $USER..."
  sudo -u "$USER" ssh-keygen -t rsa -b 4096 -N "" -f "$KEY_PATH"
else
  echo "[!] SSH key already exists for $USER at $KEY_PATH"
fi

# Ensure SSH directory and permissions are correct
sudo -u "$USER" mkdir -p /home/$USER/.ssh
sudo chmod 700 /home/$USER/.ssh
sudo chmod 600 "$KEY_PATH"
sudo chmod 644 "$KEY_PATH.pub"

# If remote host is specified, copy the key there
if [ -n "$REMOTE_HOST" ]; then
  echo "[+] Copying public key to $REMOTE_HOST..."
  sudo -u "$USER" ssh-copy-id -i "$KEY_PATH.pub" "$USER@$REMOTE_HOST"
fi

echo "[✔] SSH key setup complete!"
