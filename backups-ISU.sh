#!/bin/bash

# Backup important directories into /root with a timestamped filename
# Requires zip to be installed

if [[ $(id -u) -ne 0 ]]; then
    echo "Error: Script must be run as root." >&2
    exit 1
fi

# Ensure zip is installed
if ! command -v zip &>/dev/null; then
    echo "Error: zip command not found. Please install it." >&2
    exit 1
fi

# Define directories to backup
backup_dirs="/etc /home /bin /var/www /usr/bin"
backup_file="/root/backup_$(date +%F_%H-%M-%S).zip"

# Create the backup
if zip -r "$backup_file" $backup_dirs; then
    echo "Backup successfully created at: $backup_file"
else
    echo "Error: Failed to create backup." >&2
    exit 1
fi
