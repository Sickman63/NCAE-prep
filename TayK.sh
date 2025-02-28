#!/bin/bash
# Advanced Ubuntu Hardening Script
# Run as root, tested on Ubuntu 22.04/24.04

# Exit if not root
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run as root."
    exit 1
fi

# Set up logging
LOGFILE="/var/log/harden_ubuntu_$(date +%Y%m%d_%H%M%S).log"
echo "Hardening started at $(date)" | tee -a "$LOGFILE"

# Function to log and execute commands
execute() {
    echo "Executing: $@" | tee -a "$LOGFILE"
    "$@" >> "$LOGFILE" 2>&1
    if [ $? -ne 0 ]; then
        echo "Error: Failed to execute '$@'" | tee -a "$LOGFILE"
        exit 1
    fi
}

# 1. System Updates
execute apt update
execute apt upgrade -y
execute apt autoremove -y

# 2. Firewall Setup (UFW with rate limiting)
execute apt install ufw -y
execute ufw default deny incoming
execute ufw default allow outgoing
execute ufw limit 22/tcp  # SSH with rate limiting
execute ufw allow 80/tcp # Example: HTTP
execute ufw allow 443/tcp # Example: HTTPS
execute ufw enable

# 3. SSH Hardening
SSH_CONFIG="/etc/ssh/sshd_config"
if [ -f "$SSH_CONFIG" ]; then
    execute sed -i 's/#PermitRootLogin.*/PermitRootLogin prohibit-password/' "$SSH_CONFIG"
    execute sed -i 's/#PasswordAuthentication.*/PasswordAuthentication no/' "$SSH_CONFIG"
    execute sed -i 's/#MaxAuthTries.*/MaxAuthTries 3/' "$SSH_CONFIG"
    execute sed -i 's/#LoginGraceTime.*/LoginGraceTime 30/' "$SSH_CONFIG"
    execute systemctl restart sshd
else
    echo "Error: SSH config file not found!" | tee -a "$LOGFILE"
fi

# 4. Install and Configure Fail2Ban
execute apt install fail2ban -y
cat <<EOF > /etc/fail2ban/jail.local
[DEFAULT]
bantime  = 3600
maxretry = 5
[sshd]
enabled = true
EOF
execute systemctl enable fail2ban
execute systemctl restart fail2ban

# 5. Kernel and Network Hardening (sysctl)
SYSCTL_CONF="/etc/sysctl.conf"
cat <<EOF >> "$SYSCTL_CONF"
# Disable IP forwarding
net.ipv4.ip_forward = 0
net.ipv6.conf.all.forwarding = 0

# Disable packet redirect acceptance
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0

# Enable TCP SYN Cookies
net.ipv4.tcp_syncookies = 1

# Disable source routing
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0

# Protect against spoofing
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
EOF
execute sysctl -p

# 6. Filesystem Hardening
execute chmod 700 /root
execute chmod 750 /etc/cron.daily
execute find /var -type d -exec chmod 755 {} \;
execute chown root:root /etc/passwd /etc/shadow /etc/group
execute chmod 644 /etc/passwd /etc/group
execute chmod 600 /etc/shadow

# 7. Disable Unused Kernel Modules
cat <<EOF > /etc/modprobe.d/blacklist.conf
blacklist floppy
blacklist pcspkr
blacklist vfat
install usb-storage /bin/true
EOF
execute update-initramfs -u

# 9. Auditd Setup for System Auditing
execute apt install auditd audispd-plugins -y
cat <<EOF > /etc/audit/rules.d/hardening.rules
# Monitor critical files
-a always,exit -F path=/etc/passwd -F perm=wa -k passwd_changes
-a always,exit -F path=/etc/shadow -F perm=wa -k shadow_changes
# Track privilege escalation
-a always,exit -F arch=b64 -S execve -C uid!=euid -k priv_escalation
EOF
execute systemctl enable auditd
execute systemctl restart auditd

# 10. Secure Shared Memory
execute mount -o remount,rw,nosuid,nodev,noexec /run/shm
echo "tmpfs /run/shm tmpfs rw,nosuid,nodev,noexec 0 0" >> /etc/fstab

# 11. Restrict Compiler Access
execute dpkg-statoverride --add root adm 750 /usr/bin/gcc || true
execute dpkg-statoverride --add root adm 750 /usr/bin/g++ || true

# 12. Check for SUID/SGID Binaries (report only)
echo "Scanning for SUID/SGID binaries..." | tee -a "$LOGFILE"
find / -perm /6000 -type f 2>/dev/null | tee -a "$LOGFILE"

# 13. Final Cleanup and Report
execute apt autoremove -y
execute apt autoclean -y
echo "Hardening completed at $(date). Review $LOGFILE for details." | tee -a "$LOGFILE"

# Optional: Reboot prompt
read -p "Reboot recommended. Reboot now? (y/N): " reboot
if [ "$reboot" = "y" ] || [ "$reboot" = "Y" ]; then
    execute reboot
fi
