#!/bin/bash

LOGFILE="/var/log/backdoor_removal.log"
BACKUP_DIR="/root/backup_$(date +%F-%T)"
mkdir -p "$BACKUP_DIR"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOGFILE"
}

# Ensure the script is run as root
if [[ $EUID -ne 0 ]]; then
    log "[!] This script must be run as root. Exiting."
    exit 1
fi

log "[*] Starting backdoor removal script. Logs stored in $LOGFILE"

# Backup important files before modifications
backup_file() {
    local file=$1
    if [[ -f "$file" ]]; then
        cp "$file" "$BACKUP_DIR/"
        log "[+] Backed up $file to $BACKUP_DIR"
    fi
}

backup_file /etc/passwd
backup_file /etc/shadow
backup_file /etc/cron* 
backup_file /root/.bashrc
backup_file /etc/systemd/system

# Disable suspicious services
suspicious_services=(atd cron sshd)
for service in "${suspicious_services[@]}"; do
    if systemctl is-active --quiet "$service"; then
        systemctl disable --now "$service"
        log "[+] Disabled $service"
    fi
    systemctl mask "$service"
done

# Find and remove common persistence mechanisms
log "[*] Scanning for unauthorized SSH keys..."
find /root /home -type f -name "authorized_keys" -exec grep -E 'ssh-rsa|ssh-dss' {} \; -exec cp {} "$BACKUP_DIR" \; -exec rm -f {} \;
log "[+] Removed unauthorized SSH keys (backups stored)."

log "[*] Checking for suspicious cron jobs..."
crontab -l | tee "$BACKUP_DIR/crontab_backup" | grep -E 'nc|bash|curl|wget|python' && crontab -r
log "[+] Cleared suspicious cron jobs (backup stored)."

log "[*] Removing hidden directories and files..."
find / -type d -name ".git" -exec rm -rf {} \;
find / -type f -name ".bash_history" -exec rm -f {} \;
log "[+] Removed hidden malicious directories and files."

# Check for reverse shell connections
log "[*] Checking for active reverse shell connections..."
suspect_connections=$(ss -antp | grep -E ':53|:443|:8080|:9001')
if [[ -n "$suspect_connections" ]]; then
    log "[!] Suspicious network connections detected:"
    log "$suspect_connections"
fi

log "[*] Hardening system against future attacks."
auditctl -w /etc/passwd -p wa -k passwd_changes
log "[+] Audit logging enabled for /etc/passwd."

log "[*] Backdoor removal process completed. Please review logs for details."