#!/bin/bash

# Check if script is run as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run this script as root or with sudo."
    exit 1
fi

# Variables
TEAM_NUM=12
INTERNAL_IP="192.168.${TEAM_NUM}.12"
EXTERNAL_IP="172.18.13.${TEAM_NUM}"
EXTERNAL_SUBNET1="13.18.172"
EXTERNAL_SUBNET2="14.18.172"
INTERNAL_SUBNET="12.168.192"

# Update system and install BIND
echo "Updating system and installing BIND..."
dnf update -y
dnf install bind bind-utils -y

# Configure /etc/named.conf
echo "Configuring /etc/named.conf..."
cat > /etc/named.conf <<EOF
options {
    listen-on port 53 { 127.0.0.1; ${INTERNAL_IP}; ${EXTERNAL_IP}; };
    listen-on-v6 { none; };
    directory "/var/named";
    dump-file "/var/named/data/cache_dump.db";
    statistics-file "/var/named/data/named_stats.txt";
    memstatistics-file "/var/named/data/named_mem_stats.txt";
    allow-query { any; };
    recursion yes;
};

zone "team${TEAM_NUM}.ncaecybergames.org" IN {
    type master;
    file "team${TEAM_NUM}.ncaecybergames.org.db";
    allow-update { none; };
};

zone "${EXTERNAL_SUBNET1}.in-addr.arpa" IN {
    type master;
    file "${EXTERNAL_SUBNET1}.rev";
    allow-update { none; };
};

zone "${EXTERNAL_SUBNET2}.in-addr.arpa" IN {
    type master;
    file "${EXTERNAL_SUBNET2}.rev";
    allow-update { none; };
};

zone "team${TEAM_NUM}.net" IN {
    type master;
    file "team${TEAM_NUM}.net.db";
    allow-update { none; };
};

zone "${INTERNAL_SUBNET}.in-addr.arpa" IN {
    type master;
    file "${INTERNAL_SUBNET}.rev";
    allow-update { none; };
};
EOF

# Create external forward zone file
echo "Creating external forward zone file..."
cat > /var/named/team${TEAM_NUM}.ncaecybergames.org.db <<EOF
\$TTL 86400
@   IN  SOA  ns1.team${TEAM_NUM}.ncaecybergames.org. admin.team${TEAM_NUM}.ncaecybergames.org. (
        2025022801  ; Serial
        3600        ; Refresh
        1800        ; Retry
        604800      ; Expire
        86400       ; Minimum TTL
)

@       IN  NS   ns1.team${TEAM_NUM}.ncaecybergames.org.

ns1     IN  A    ${EXTERNAL_IP}
www     IN  A    ${EXTERNAL_IP}
shell   IN  A    172.18.14.${TEAM_NUM}
files   IN  A    172.18.14.${TEAM_NUM}
EOF

# Create internal forward zone file
echo "Creating internal forward zone file..."
cat > /var/named/team${TEAM_NUM}.net.db <<EOF
\$TTL 86400
@   IN  SOA  ns1.team${TEAM_NUM}.net. admin.team${TEAM_NUM}.net. (
        2025022801  ; Serial
        3600        ; Refresh
        1800        ; Retry
        604800      ; Expire
        86400       ; Minimum TTL
)

@       IN  NS   ns1.team${TEAM_NUM}.net.

www     IN  A    192.168.${TEAM_NUM}.5
db      IN  A    192.168.${TEAM_NUM}.7
ns1     IN  A    ${INTERNAL_IP}
EOF

# Create external reverse zone file (13.18.172)
echo "Creating external reverse zone file for ${EXTERNAL_SUBNET1}..."
cat > /var/named/${EXTERNAL_SUBNET1}.rev <<EOF
\$TTL 86400
@   IN  SOA  ns1.team${TEAM_NUM}.ncaecybergames.org. admin.team${TEAM_NUM}.ncaecybergames.org. (
        2025022801  ; Serial
        3600        ; Refresh
        1800        ; Retry
        604800      ; Expire
        86400       ; Minimum TTL
)

@       IN  NS   ns1.team${TEAM_NUM}.ncaecybergames.org.

${TEAM_NUM}      IN  PTR  ns1.team${TEAM_NUM}.ncaecybergames.org.
${TEAM_NUM}      IN  PTR  www.team${TEAM_NUM}.ncaecybergames.org.
EOF

# Create external reverse zone file (14.18.172)
echo "Creating external reverse zone file for ${EXTERNAL_SUBNET2}..."
cat > /var/named/${EXTERNAL_SUBNET2}.rev <<EOF
\$TTL 86400
@   IN  SOA  ns1.team${TEAM_NUM}.ncaecybergames.org. admin.team${TEAM_NUM}.ncaecybergames.org. (
        2025022801  ; Serial
        3600        ; Refresh
        1800        ; Retry
        604800      ; Expire
        86400       ; Minimum TTL
)

@       IN  NS   ns1.team${TEAM_NUM}.ncaecybergames.org.

${TEAM_NUM}      IN  PTR  shell.team${TEAM_NUM}.ncaecybergames.org.
${TEAM_NUM}      IN  PTR  files.team${TEAM_NUM}.ncaecybergames.org.
EOF

# Create internal reverse zone file
echo "Creating internal reverse zone file..."
cat > /var/named/${INTERNAL_SUBNET}.rev <<EOF
\$TTL 86400
@   IN  SOA  ns1.team${TEAM_NUM}.net. admin.team${TEAM_NUM}.net. (
        2025022801  ; Serial
        3600        ; Refresh
        1800        ; Retry
        604800      ; Expire
        86400       ; Minimum TTL
)

@       IN  NS   ns1.team${TEAM_NUM}.net.

5       IN  PTR  www.team${TEAM_NUM}.net.
7       IN  PTR  db.team${TEAM_NUM}.net.
${TEAM_NUM}      IN  PTR  ns1.team${TEAM_NUM}.net.
EOF

# Set permissions
echo "Setting file permissions..."
chown named:named /var/named/*.db /var/named/*.rev
chmod 640 /var/named/*.db /var/named/*.rev

# Validate configuration
echo "Validating configuration..."
named-checkconf /etc/named.conf
if [ $? -ne 0 ]; then
    echo "Error in /etc/named.conf. Check syntax and try again."
    exit 1
fi

for zone in "team${TEAM_NUM}.ncaecybergames.org" "${EXTERNAL_SUBNET1}.in-addr.arpa" "${EXTERNAL_SUBNET2}.in-addr.arpa" "team${TEAM_NUM}.net" "${INTERNAL_SUBNET}.in-addr.arpa"; do
    named-checkzone $zone /var/named/${zone//in-addr.arpa/rev}.db
    if [ $? -ne 0 ]; then
        echo "Error in zone $zone. Check file and try again."
        exit 1
    fi
done

# Start and enable BIND
echo "Starting and enabling named service..."
systemctl start named
systemctl enable named

# Configure firewall
echo "Configuring firewall..."
firewall-cmd --add-service=dns --permanent
firewall-cmd --reload

# Basic test
echo "Performing basic DNS tests..."
dig @${INTERNAL_IP} ns1.team${TEAM_NUM}.net > /tmp/dns_test_internal.log 2>&1
dig @${EXTERNAL_IP} ns1.team${TEAM_NUM}.ncaecybergames.org > /tmp/dns_test_external.log 2>&1

if systemctl is-active named >/dev/null; then
    echo "DNS setup completed successfully! Check /tmp/dns_test_*.log for initial test results."
else
    echo "DNS service failed to start. Check logs with 'journalctl -u named'."
    exit 1
fi
