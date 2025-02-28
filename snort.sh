#!/bin/bash

# Check for root privileges
if [ "$EUID" -ne 0 ]; then
    echo "Please run this script as root or with sudo"
    exit 1
fi

# Log file
LOG_FILE="/var/log/snort_setup.log"
echo "Script started at $(date)" > "$LOG_FILE"

# 1. Update and upgrade the system
echo "Updating system..." | tee -a "$LOG_FILE"
apt update && apt upgrade -y || { echo "System update failed" | tee -a "$LOG_FILE"; exit 1; }

# 2. Install Snort
echo "Installing Snort..." | tee -a "$LOG_FILE"
apt install -y snort || { echo "Snort installation failed" | tee -a "$LOG_FILE"; exit 1; }

# 3. Configure network interface for monitoring
# Assume eth0 is the monitoring interface (connected to SPAN port or Team Router)
MONITOR_INTERFACE="eth0"
INTERNAL_LAN="192.168.0.0/24"
EXTERNAL_LAN="172.18.0.0/16"
SNORT_CONF="/etc/snort/snort.conf"

# Backup existing Snort configuration
cp "$SNORT_CONF" "$SNORT_CONF.bak" || echo "No existing Snort config to backup" | tee -a "$LOG_FILE"

# Configure Snort settings
echo "Configuring Snort..." | tee -a "$LOG_FILE"
cat > "$SNORT_CONF" << EOF
# Snort configuration for N-CAE Cyber Games Blue Team
config daemon
config interface: $MONITOR_INTERFACE
config order: event queue config
config event_queue: max_queue 8 log 5 order_events priority

# Define networks
ipvar HOME_NET $INTERNAL_LAN,$EXTERNAL_LAN
ipvar EXTERNAL_NET !$HOME_NET

# Output configuration
output unified2: filename snort.log, limit 128

# Include rules
include \$RULE_PATH/community.rules
include \$RULE_PATH/local.rules
EOF

# 4. Download and install Snort community rules
echo "Downloading Snort community rules..." | tee -a "$LOG_FILE"
wget -O /tmp/community-rules.tar.gz https://www.snort.org/downloads/community/snort3-community-rules.tar.gz || { echo "Failed to download rules" | tee -a "$LOG_FILE"; exit 1; }
tar -xzf /tmp/community-rules.tar.gz -C /etc/snort/rules/ || { echo "Failed to extract rules" | tee -a "$LOG_FILE"; exit 1; }

# 5. Create custom local rules for Blue Team assets
echo "Creating custom Snort rules..." | tee -a "$LOG_FILE"
cat > /etc/snort/rules/local.rules << EOF
# Custom rules for N-CAE Cyber Games Blue Team
alert tcp any any -> 192.168.1.5 22 (msg:"SSH Attempt on Web Server"; sid:1000001; rev:1;)
alert tcp any any -> 192.168.1.5 80 (msg:"HTTP Traffic to Web Server"; sid:1000002; rev:1;)
alert tcp any any -> 192.168.1.5 443 (msg:"HTTPS Traffic to Web Server"; sid:1000003; rev:1;)
alert udp any any -> 192.168.1.12 53 (msg:"DNS Query to DNS Server"; sid:1000004; rev:1;)
alert tcp 192.168.1.10 any -> any 445 (msg:"SMB Traffic from Internal Kali VM"; sid:1000005; rev:1;)
alert tcp any any -> 172.18.15.t 22 (msg:"SSH Attempt on External Kali VM"; sid:1000006; rev:1;)
EOF

# 6. Enable IP forwarding (if monitoring via SPAN or router mirror)
echo "Enabling IP forwarding..." | tee -a "$LOG_FILE"
echo 1 > /proc/sys/net/ipv4/ip_forward
sysctl -w net.ipv4.ip_forward=1

# 7. Test Snort configuration
echo "Testing Snort configuration..." | tee -a "$LOG_FILE"
snort -T -c "$SNORT_CONF" || { echo "Snort configuration test failed" | tee -a "$LOG_FILE"; exit 1; }

# 8. Set up Snort to run as a service
echo "Setting up Snort service..." | tee -a "$LOG_FILE"
systemctl enable snort
systemctl start snort || { echo "Failed to start Snort service" | tee -a "$LOG_FILE"; exit 1; }

# 9. Verify Snort is running and monitoring
echo "Verifying Snort setup..." | tee -a "$LOG_FILE"
if systemctl is-active snort | grep -q "active"; then
    echo "Snort is running successfully" | tee -a "$LOG_FILE"
else
    echo "Snort failed to start" | tee -a "$LOG_FILE"
    exit 1
fi

# 10. Generate test traffic to verify alerts (optional, manual step reminder)
echo "To test alerts, generate traffic (e.g., ping, SSH, or HTTP to 192.168.1.5 or 192.168.1.12)" | tee -a "$LOG_FILE"
echo "Check alerts in /var/log/snort/alert" | tee -a "$LOG_FILE"

echo "Snort setup completed at $(date). Check $LOG_FILE for details."
