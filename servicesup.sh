#!/bin/bash
# USAGE:
#   sudo ./servicesup.sh service1 service2 ...
#
# This script continuously monitors the given services every 5 seconds.
# If a service is down, it attempts to restart it.

# Define color variables for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'  # No Color

# Ensure the script is run as root
if [ "$(id -u)" -ne 0 ]; then
  echo -e "${RED}This script must be run as root${NC}" >&2
  exit 1
fi

# Determine which service management tool is available
if command -v systemctl &>/dev/null; then
  SERVICE_CMD="systemctl"
elif command -v service &>/dev/null; then
  SERVICE_CMD="service"
else
  echo -e "${RED}No supported service management tool found (systemctl, service). Exiting.${NC}"
  exit 1
fi

echo -e "Using service manager: ${GREEN}$SERVICE_CMD${NC}"

# Function to check service status
check_service_status() {
  local service="$1"
  case "$SERVICE_CMD" in
    systemctl) systemctl is-active --quiet "$service" ;;
    service) service "$service" status &>/dev/null ;;
    *) return 1 ;;
  esac
}

# Function to restart a service
restart_service() {
  local service="$1"
  echo -e "${YELLOW}Attempting to restart ${service}...${NC}"
  case "$SERVICE_CMD" in
    systemctl) systemctl restart "$service" 2>/dev/null ;;
    service) service "$service" restart 2>/dev/null ;;
    *) return 1 ;;
  esac
}

# Main loop: check services every 5 seconds
while true; do
  for service in "$@"; do
    # Handle FTP service name specifically
    if [ "$service" == "ftp" ]; then
      service="vsftpd"  # Correct the service name
    fi

    check_service_status "$service"
    if [ $? -ne 0 ]; then
      echo -e "${RED}Service '$service' is down! Restarting...${NC}"
      restart_service "$service"
      sleep 2
      check_service_status "$service"
      if [ $? -eq 0 ]; then
        echo -e "${GREEN}Service '$service' restarted successfully!${NC}"
      else
        echo -e "${YELLOW}Failed to restart service '$service'. Manual intervention required.${NC}"
      fi
    else
      echo -e "${GREEN}Service '$service' is running.${NC}"
    fi
  done
  sleep 5  # Adjusted to check every 5 seconds
done
