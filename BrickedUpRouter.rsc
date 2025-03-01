# MikroTik Router Hardening Script for NCAE Cyber Games (Proxmox Setup, Optional Jumphost, Updated for Scoring)
# Configures Team Router (ether1: 172.18.13.12, ether2: 192.168.12.1)
# Includes hardening, firewall rules, deception, monitoring, and advanced disruption

# 1. Initial Setup and Secure Access
# Change default admin password (using the provided strong password)
/user set admin password=Tr0ub4dor&3x
/user remove [find name!="admin"]

# Disable unnecessary services but allow SSH and WinBox from Jumphost (172.18.12.15)
/ip service
set telnet disabled=yes
set ftp disabled=yes
set www disabled=yes
set api disabled=yes
set winbox address=172.18.12.15/32
set ssh address=172.18.12.15/32 port=2222

# 2. Configure Network Interfaces
/ip address
# Remove existing IPs to avoid conflicts
remove [find]
# Set IPs for ether1 (External LAN) and ether2 (Team LAN)
add address=172.18.13.12/16 interface=ether1
add address=192.168.12.1/24 interface=ether2

# Enable NAT masquerading for Team LAN to access External LAN
/ip firewall nat
remove [find dynamic=no]
add chain=srcnat action=masquerade out-interface=ether1

# 3. Harden the Router
# Disable unnecessary features
/ip upnp set enabled=no
/ip dns set allow-remote-requests=no
/ip neighbor discovery-settings set discover-interface-list=none
/ip proxy set enabled=no
/ip socks set enabled=no
/ppp profile set *0 disabled=yes

# Secure ARP to prevent spoofing
/interface ethernet
set ether1 arp=reply-only
set ether2 arp=reply-only

# Enable logging to Gravwell (172.18.16.122)
/system logging action
add name=remote target=remote remote=172.18.16.122
/system logging
add topics=info action=remote
add topics=error action=remote
add topics=warning action=remote

# 4. Configure Firewall Rules
# Clear existing firewall rules
/ip firewall filter remove [find]
/ip firewall nat remove [find dynamic=no]
/ip firewall mangle remove [find]

# Input Chain (Traffic to the Router)
/ip firewall filter
add chain=input action=accept src-address=172.18.12.15 dst-port=2222 protocol=tcp comment="Allow SSH from Jumphost" log=yes log-prefix="Jumphost_SSH"
add chain=input action=accept src-address=172.18.12.15 dst-port=8291 protocol=tcp comment="Allow WinBox from Jumphost" log=yes log-prefix="Jumphost_WinBox"
add chain=input action=accept connection-state=established,related comment="Allow Established/Related"
# Allow ICMP ping for Scoring Engine (increased limit for reliability)
add chain=input action=accept protocol=icmp icmp-options=8:0 limit=50,5 comment="Allow ICMP Ping for Scoring Engine"
add chain=input action=drop protocol=icmp comment="Drop Excess ICMP and Prevent Tunneling" log=yes log-prefix="ICMP_Drop"
# Tarpit Red Team attempts on SSH, Telnet, FTP, SMB, and others
add chain=input action=tarpit protocol=tcp src-address=172.18.15.0/24 dst-port=22 comment="Tarpit Red Team SSH Attempts" log=yes log-prefix="RedTeam_Tarpit"
add chain=input action=tarpit protocol=tcp src-address=172.18.15.0/24 dst-port=23 comment="Tarpit Red Team Telnet Attempts" log=yes log-prefix="RedTeam_Tarpit"
add chain=input action=tarpit protocol=tcp src-address=172.18.15.0/24 dst-port=21 comment="Tarpit Red Team FTP Attempts" log=yes log-prefix="RedTeam_Tarpit"
add chain=input action=tarpit protocol=tcp src-address=172.18.15.0/24 dst-port=445 comment="Tarpit Red Team SMB Attempts" log=yes log-prefix="RedTeam_Tarpit"
add chain=input action=tarpit protocol=tcp src-address=172.18.15.0/24 dst-port=3389 comment="Tarpit Red Team RDP Attempts" log=yes log-prefix="RedTeam_Tarpit"
# Block port scans
add chain=input action=add-src-to-address-list address-list=port-scanners address-list-timeout=2w protocol=tcp tcp-flags=fin,!syn,!rst,!psh,!ack,!urg
add chain=input action=add-src-to-address-list address-list=port-scanners address-list-timeout=2w protocol=tcp tcp-flags=fin,syn
add chain=input action=drop src-address-list=port-scanners comment="Drop Port Scanners"
# Drop all other input traffic
add chain=input action=drop comment="Drop All Other Input" log=yes log-prefix="Dropped_Input"

# Forward Chain (Traffic Through the Router)
/ip firewall filter
# Allow Jumphost to access Team LAN (if used)
add chain=forward action=accept src-address=172.18.12.15 dst-address=192.168.12.0/24 comment="Allow Jumphost to Team LAN" log=yes log-prefix="Jumphost_TeamLAN"
# Allow Scoring Engine to access Team LAN services
add chain=forward action=accept src-address=0.0.0.0/0 dst-address=192.168.12.5 dst-port=80 protocol=tcp comment="Allow Scoring Engine to Web (WWW Port 80, WWW Content)"
add chain=forward action=accept src-address=0.0.0.0/0 dst-address=192.168.12.5 dst-port=443 protocol=tcp comment="Allow Scoring Engine to Web SSL"
add chain=forward action=accept src-address=0.0.0.0/0 dst-address=192.168.12.12 dst-port=53 protocol=udp comment="Allow Scoring Engine to DNS (DNS EXT REV, DNS EXT FWD)"
add chain=forward action=accept src-address=0.0.0.0/0 dst-address=192.168.12.7 dst-port=5432 protocol=tcp comment="Allow Scoring Engine to Postgres (Postgres Access)"
add chain=forward action=accept src-address=0.0.0.0/0 dst-address=192.168.12.15 dst-port=21 protocol=tcp comment="Allow Scoring Engine to FTP (FTP Write, FTP Read, FTP Login)"
add chain=forward action=accept src-address=0.0.0.0/0 dst-address=192.168.12.15 dst-port=50000-51000 protocol=tcp comment="Allow FTP Passive Ports"
add chain=forward action=accept src-address=0.0.0.0/0 dst-address=192.168.12.15 dst-port=22 protocol=tcp comment="Allow Scoring Engine to SSH (SSH Login)"
# Allow Team LAN to access Competition DNS, CA, and Gravwell
add chain=forward action=accept src-address=192.168.12.0/24 dst-address=172.18.0.12 dst-port=53 protocol=udp comment="Allow Team LAN to Competition DNS"
add chain=forward action=accept src-address=192.168.12.0/24 dst-address=172.18.0.38 dst-port=443 protocol=tcp comment="Allow Team LAN to CA"
add chain=forward action=accept src-address=192.168.12.0/24 dst-address=172.18.16.122 comment="Allow Team LAN to Gravwell"
# Allow established/related connections
add chain=forward action=accept connection-state=established,related comment="Allow Established/Related"
# Drop invalid connections
add chain=forward action=drop connection-state=invalid comment="Drop Invalid Connections"
# Drop fragmented packets
add chain=forward action=drop fragment=yes comment="Drop Fragmented Packets"
# Rate limit SSH to prevent brute force
add chain=forward action=add-src-to-address-list address-list=brute-force address-list-timeout=1h protocol=tcp dst-address=192.168.12.0/24 dst-port=22 connection-limit=5,32
add chain=forward action=drop src-address-list=brute-force comment="Drop Brute Force Attackers"
# Rate limit DNS to prevent tunneling
add chain=forward action=add-src-to-address-list address-list=dns-abuse address-list-timeout=1h src-address=192.168.12.0/24 dst-port=53 protocol=udp packet-size=128-65535
add chain=forward action=drop src-address-list=dns-abuse comment="Drop DNS Tunneling Attempts" log=yes log-prefix="DNS_Abuse"
# Block Red Team Kali VMs
add chain=forward action=drop src-address=172.18.15.0/24 dst-address=192.168.12.0/24 comment="Block Red Team Kali VMs to Team LAN"
# Block Team LAN outbound to Red Team Kali VMs (prevent exfiltration)
add chain=forward action=drop src-address=192.168.12.0/24 dst-address=172.18.15.0/24 comment="Block Team LAN to Red Team Kali VMs"
# Block common exploit and reverse shell ports
add chain=forward action=add-src-to-address-list address-list=suspicious-outbound address-list-timeout=1h src-address=192.168.12.0/24 dst-port=4444 protocol=tcp
add chain=forward action=add-src-to-address-list address-list=suspicious-outbound address-list-timeout=1h src-address=192.168.12.0/24 dst-port=5555 protocol=tcp
add chain=forward action=drop src-address-list=suspicious-outbound comment="Block Suspicious Outbound (e.g., Reverse Shells)" log=yes log-prefix="Suspicious_Outbound"
# Log high-risk port access attempts
add chain=forward action=log src-address=172.18.15.0/24 dst-port=3389 protocol=tcp log-prefix="RedTeam_RDP_Attempt"
add chain=forward action=log src-address=172.18.15.0/24 dst-port=5900 protocol=tcp log-prefix="RedTeam_VNC_Attempt"
# Drop all other forward traffic
add chain=forward action=drop comment="Drop All Other Forward" log=yes log-prefix="Dropped_Forward"

# 5. Enhanced Deception Techniques
# Redirect Red Team attempts to fake services
/ip firewall nat
add chain=dstnat dst-address=172.18.13.12 dst-port=23 protocol=tcp action=dst-nat to-addresses=192.168.12.5 to-ports=80 comment="Fake Telnet Service"
add chain=dstnat dst-address=172.18.13.12 dst-port=21 protocol=tcp action=dst-nat to-addresses=192.168.12.5 to-ports=80 comment="Fake FTP Service"
add chain=dstnat dst-address=172.18.13.12 dst-port=445 protocol=tcp action=dst-nat to-addresses=192.168.12.5 to-ports=80 comment="Fake SMB Service"
add chain=dstnat dst-address=172.18.13.12 dst-port=8080 protocol=tcp action=dst-nat to-addresses=192.168.12.5 to-ports=80 comment="Fake HTTP Service"
add chain=dstnat src-address=172.18.15.0/24 dst-port=22 protocol=tcp action=dst-nat to-addresses=192.168.12.41 to-ports=2222 comment="Redirect Red Team SSH to Honeypot"
# Force Team LAN DNS traffic to Competition DNS
add chain=dstnat src-address=192.168.12.0/24 dst-port=53 protocol=udp action=dst-nat to-addresses=172.18.0.12 comment="Force DNS to Competition DNS"
# Respond to scans on unused IPs
add chain=dstnat dst-address=192.168.12.100-192.168.12.200 action=dst-nat to-addresses=192.168.12.5 to-ports=80 comment="Fake Hosts for Red Team Scans"
# Blackhole Red Team traffic
/ip route
add dst-address=172.18.15.0/24 type=blackhole comment="Blackhole Red Team Traffic"
# Fake ARP entries to confuse Red Team
/ip arp
add address=192.168.12.254 mac-address=00:11:22:33:44:55 interface=ether2 comment="Fake ARP Entry"
add address=192.168.12.253 mac-address=00:11:22:33:44:56 interface=ether2 comment="Fake ARP Entry 2"

# 6. Disrupt Red Team Tools
# Mess with Nmap scans by rewriting TTL
/ip firewall mangle
add chain=prerouting src-address=172.18.15.0/24 action=change-ttl new-ttl=set:255 passthrough=yes comment="Break Nmap TTL Fingerprinting"
# Mark Red Team traffic for logging
add chain=prerouting src-address=172.18.15.0/24 action=mark-connection new-connection-mark=red-team passthrough=yes
# Detect repetitive C2 traffic
add chain=forward action=add-src-to-address-list address-list=c2-traffic address-list-timeout=1h src-address=192.168.12.0/24 connection-limit=10,32
add chain=forward action=log src-address-list=c2-traffic log-prefix="C2_Traffic_Detected"

# 7. Advanced Monitoring
# Packet capture for Red Team traffic
/tool sniffer
set filter-ip-address=172.18.15.0/24 file-name=red-team-traffic.pcap
start

# 8. Rapid Recovery
# Backup configuration
/export file=router-config
# Schedule periodic backups to the Backup VM (192.168.12.15, update FTP credentials)
/system scheduler
add name=backup interval=1h on-event=":execute export file=router-config; /tool fetch address=192.168.12.15 src-path=router-config.rsc mode=ftp user=admin password=Tr0ub4dor&3x dst-path=router-config.rsc"
# Backup route (if primary gateway fails)
/ip route
add dst-address=0.0.0.0/0 gateway=192.168.12.41 distance=2 comment="Backup Route via Kali VM"

# 9. Finalize and Log
:log info "Router configuration complete. Red Team infiltration made insanely hard (Proxmox setup, optional Jumphost access, scoring rules applied)!"
