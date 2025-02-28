#!/bin/bash

# Check if the script is run as root
if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root" >&2
  exit 1
fi

# Get the operating system ID
id_like_line=$(grep '^ID=' /etc/os-release)
operatingSystem=$(echo $id_like_line | cut -d'=' -f2 | tr -d '"')

# Function to validate IP address format
function validate_ip() {
  local ip="$1"
  # Check for a valid IP address using a regex pattern
  if [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
    # Split the IP into octets and validate each
    IFS='.' read -r i1 i2 i3 i4 <<< "$ip"
    if [ "$i1" -le 255 ] && [ "$i2" -le 255 ] && [ "$i3" -le 255 ] && [ "$i4" -le 255 ]; then
      return 0
    fi
  fi
  return 1
}

# Check if IP address is provided
if [ $# -eq 0 ]; then
  echo "Not blocking IP addresses - no IP supplied" >&2
  exit 1
fi

# Validate the supplied IP address
if ! validate_ip "$1"; then
  echo "Invalid IP address format: $1" >&2
  exit 1
fi

# Block the IP address based on the operating system
if [ "$operatingSystem" = "debian" ] || [ "$operatingSystem" = "ubuntu" ]; then
  iptables -I INPUT -s "$1" -j DROP || { echo "Failed to block incoming traffic from $1" >&2; exit 1; }
  iptables -I OUTPUT -d "$1" -j DROP || { echo "Failed to block outgoing traffic to $1" >&2; exit 1; }
  iptables-save > /etc/iptables/rules.v4 || { echo "Failed to save iptables rules" >&2; exit 1; }
  ip6tables-save > /etc/iptables/rules.v6 || { echo "Failed to save ip6tables rules" >&2; exit 1; }
  echo "Blocked IP address $1 on Debian/Ubuntu"

elif [ "$operatingSystem" = "fedora" ] || [ "$operatingSystem" = "centos" ]; then
  iptables -I INPUT -s "$1" -j DROP || { echo "Failed to block incoming traffic from $1" >&2; exit 1; }
  iptables -I OUTPUT -d "$1" -j DROP || { echo "Failed to block outgoing traffic to $1" >&2; exit 1; }
  service iptables save || { echo "Failed to save iptables rules" >&2; exit 1; }
  systemctl enable iptables || { echo "Failed to enable iptables service" >&2; exit 1; }
  echo "Blocked IP address $1 on Fedora/CentOS"
else
  echo "Unsupported operating system: $operatingSystem" >&2
  exit 1
fi

# Log the blocked IP address
echo "$(date): Blocked IP address $1" >> /var/log/iptables_block.log
