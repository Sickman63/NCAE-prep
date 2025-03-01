#!/bin/bash

# FTP Setup & Hardening Script (vsftpd) - Port 2121
# Configures FTP on 172.18.14.12 with security best practices

FTP_CONF="/etc/vsftpd.conf"
FTP_USER="ftpuser"
FTP_PASS="SecurePass123!"
FTP_DIR="/home/$FTP_USER/ftp"
SSL_CERT="/etc/ssl/certs/vsftpd.pem"
SSL_KEY="/etc/ssl/private/vsftpd.pem"
FTP_PORT=2121

# Ensure script is run as root
if [[ $EUID -ne 0 ]]; then
    echo "[!] This script must be run as root. Use sudo."
    exit 1
fi

# Install vsftpd
echo "[+] Installing vsftpd..."
apt update && apt install -y vsftpd openssl fail2ban ufw || {
    echo "[!] Failed to install required packages!"
    exit 1
}

# Create FTP user
if ! id "$FTP_USER" &>/dev/null; then
    echo "[+] Creating FTP user: $FTP_USER"
    useradd -m -s /usr/sbin/nologin "$FTP_USER"
    echo "$FTP_USER:$FTP_PASS" | chpasswd
fi

# Create FTP directory and set permissions
echo "[+] Configuring FTP directory..."
mkdir -p "$FTP_DIR"
chown "$FTP_USER:$FTP_USER" "$FTP_DIR"
chmod 750 "$FTP_DIR"

# Configure vsftpd
echo "[+] Writing vsftpd configuration..."
cat > "$FTP_CONF" << EOF
listen=YES
listen_ipv6=NO
anonymous_enable=NO
local_enable=YES
write_enable=YES
chroot_local_user=YES
allow_writeable_chroot=YES
local_root=$FTP_DIR
pam_service_name=vsftpd
ssl_enable=YES
rsa_cert_file=$SSL_CERT
rsa_private_key_file=$SSL_KEY
force_local_data_ssl=YES
force_local_logins_ssl=YES
pasv_enable=YES
pasv_min_port=40000
pasv_max_port=40100
listen_port=$FTP_PORT
EOF

# Generate SSL certificate for FTPS if not exists
if [[ ! -f "$SSL_CERT" ]]; then
    echo "[+] Generating SSL certificate for FTPS..."
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$SSL_KEY" -out "$SSL_CERT" \
        -subj "/CN=$(hostname)"
    chmod 600 "$SSL_KEY"
fi

# Restart vsftpd service
echo "[+] Restarting vsftpd..."
systemctl restart vsftpd
systemctl enable vsftpd

# Set up firewall rules
echo "[+] Configuring firewall..."
ufw allow $FTP_PORT/tcp
ufw allow 40000:40100/tcp
ufw enable

# Configure fail2ban for FTP protection
echo "[+] Configuring fail2ban..."
cat > /etc/fail2ban/jail.local << EOF
[vsftpd]
enabled = true
port = $FTP_PORT
filter = vsftpd
logpath = /var/log/vsftpd.log
maxretry = 5
bantime = 3600
EOF
systemctl restart fail2ban

echo "[✔] FTP setup complete on 172.18.14.12!"
echo "[i] Connect using: ftp 172.18.14.12 $FTP_PORT (plain) or FTPS (secure)"

