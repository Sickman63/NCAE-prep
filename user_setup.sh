#!/bin/bash

# Disable sudo access for all users except root
echo "Disabling sudo access for all users except root..."
sudo sed -i '/%sudo/d' /etc/sudoers
sudo sed -i '/%wheel/d' /etc/sudoers

# Prompt for new username
read -p "Enter new username: " new_user

# Create new user with home directory (-m)
sudo useradd -m "$new_user"

# Set password securely
echo "Set password for $new_user:"
sudo passwd "$new_user"

echo "User $new_user created successfully."
