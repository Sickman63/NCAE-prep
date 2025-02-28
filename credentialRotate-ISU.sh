#!/bin/bash
# This will rotate all SSH keys and passwords, logging as required. User will be prompted for the password.

# Excluded users from password changes
excludeUser=(
    "blackteam_adm"
    "root"
)

# Get the hostname
hostname=$(hostname)

# Directory for shared SSH keys
keyDir="/etc/ssh/shared_keys"
mkdir -p "$keyDir"

# Shared SSH key
sshKey="$keyDir/shared_key"
if [ ! -f "$sshKey" ]; then
    ssh-keygen -t rsa -b 4096 -f "$sshKey" -N ''
    echo "Shared SSH key pair generated."
else
    echo "Shared SSH key pair already exists."
fi

# Prompt for new passphrase
echo "Enter the new passphrase for all users (except for logging $excludeUser):"
read -s sharedPassphrase

if [[ -z "$sharedPassphrase" ]]; then
    echo "Passphrase cannot be empty. Exiting..."
    exit 1
fi

# Log file for actions taken
LOG_FILE="/var/log/ssh_rotation.log"

# Function to log messages
log_message() {
    echo "$(date): $1" >> "$LOG_FILE"
}

# Loop through all users
getent passwd | while IFS=: read -r username password uid gid full home shell; do
    if [[ ! " ${excludeUser[@]} " =~ " ${username} " ]]; then
        if [[ "$shell" == *sh ]]; then
            # Change user password
            echo "$username:$sharedPassphrase" | chpasswd
            if [ $? -eq 0 ]; then
                echo "Password changed for $username"
                log_message "Password changed for $username"
            else
                echo "Failed to change password for $username"
                log_message "Failed to change password for $username"
                continue
            fi
            
            # Set up SSH directory and authorized_keys
            userSshDir="$home/.ssh"
            mkdir -p "$userSshDir"
            echo "" > "$userSshDir/authorized_keys"
            chown -R "$username":"$gid" "$userSshDir" 
            chmod 700 "$userSshDir"  # Secure the .ssh directory
            chmod 600 "$userSshDir/authorized_keys"  # Secure the authorized_keys file
            echo "Shared SSH keys set for $username."
            log_message "Shared SSH keys set for $username."
        fi
    fi
done

# Changing root user password
passwd

echo "Script completed."
log_message "Script completed."
