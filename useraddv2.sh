#!/bin/bash

# 1. Disable direct root login via SSH:
echo "Disabling direct root login..."
sudo sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sudo systemctl restart sshd

# 2. Prompt for new username:
read -p "Enter new username: " new_user

# 3. Create new user with a home directory and default shell:
sudo useradd -m -s /bin/bash "$new_user"

# 4. Set the password securely (input will be hidden):
echo "Set password for $new_user:"
sudo passwd "$new_user"

# 5. Add the new user to the sudo group (for Debian/Ubuntu; for RHEL/CentOS use 'wheel'):
sudo usermod -aG sudo "$new_user"

echo "User '$new_user' has been created with sudo privileges. Direct root login is disabled."
