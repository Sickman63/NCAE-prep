#!/bin/bash

# Ensure the script is run as root
if [[ $(id -u) -ne 0 ]]; then
    echo "Please run this script as root or using sudo."
    exit 1
fi

# Update package lists
apt update -y

# Install AIDE
apt install aide -y

# Initialize AIDE database
aideinit -y

# Move the new database to the official location
mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db

# Set up a cron job to run AIDE check daily
CRON_JOB="0 3 * * * /usr/bin/aide.wrapper --check | mail -s 'AIDE Integrity Check Report' root"
(crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -

# Print completion message
echo "AIDE installation and initial setup complete. AIDE will check for changes daily at 3 AM and send reports to root."
