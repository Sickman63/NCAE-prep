#!/bin/bash
# Continuously display the 5 most-recently modified .service files along with their ExecStart= line.
# On the initial run, only display the services.
# After that, if a new service appears, it is included in the display and then you are prompted
# to stop and delete it.

# Default directories to search for .service files.
SERVICE_DIRS=(/etc/systemd/system /lib/systemd/system)

# Check for command-line arguments to override default directories
if [ "$#" -gt 0 ]; then
    SERVICE_DIRS=("$@")
fi

# Colors for ranking (most recent to 5th).
COLORS=( "\e[31m" "\e[33m" "\e[32m" "\e[36m" "\e[34m" )
RESET="\e[0m"

# Associative array to keep track of seen services and their modification times.
declare -A known_services

# Log file for actions taken
LOG_FILE="/var/log/service_monitor.log"

first_run=true

# Function to log messages
log_message() {
    echo "$(date): $1" >> "$LOG_FILE"
}

trap "echo -e '\nExiting script...'; exit" SIGINT

while true; do
    clear
    echo "Updated: $(date)"
    echo "------------------------------------------------------------"

    # Get the top 5 most-recently modified .service files.
    mapfile -t lines < <(find "${SERVICE_DIRS[@]}" -type f -name "*.service" -printf "%T@ %p\n" 2>/dev/null \
                         | sort -k1,1nr | head -5)

    new_services=()  # Array to hold services that are new or updated this iteration.
    count=0

    for line in "${lines[@]}"; do
        # Extract the epoch time and file path.
        epoch=$(echo "$line" | awk '{print $1}')
        file=$(echo "$line" | cut -d' ' -f2-)
        service_name=$(basename "$file")

        # If the service file is new or its modification time has changed,
        # mark it as new (except on the very first run).
        if [[ -z "${known_services[$file]}" || "${known_services[$file]}" != "$epoch" ]]; then
            if [ "$first_run" = false ]; then
                new_services+=("$file")
            fi
            known_services["$file"]="$epoch"
        fi

        # Get the first ExecStart= line (or use a placeholder if not found).
        exec_line=$(grep -m 1 -E '^ExecStart=' "$file" 2>/dev/null)
        [ -z "$exec_line" ] && exec_line="ExecStart=(none)"

        # Print the service and its ExecStart= side by side.
        color=${COLORS[$count]}
        printf "${color}Service: %-50s${RESET}  %s\n" "$file" "$exec_line"
        count=$((count + 1))
    done

    # After displaying the list, prompt for each new/updated service.
    if [ "$first_run" = false ]; then
        for file in "${new_services[@]}"; do
            service_name=$(basename "$file")
            echo -e "\nNew service detected: $file"
            while true; do
                read -p "Do you want to stop and delete '$service_name'? (y/n): " answer
                if [[ "$answer" =~ ^[Yy]$ ]]; then
                    echo "Stopping $service_name..."
                    if sudo systemctl stop "$service_name"; then
                        echo "Deleting $service_name from $file..."
                        if sudo rm "$file"; then
                            echo "Successfully deleted $service_name."
                            log_message "Deleted service: $service_name from $file."
                        else
                            echo "Failed to delete $service_name from $file."
                        fi
                    else
                        echo "Failed to stop $service_name."
                    fi
                    echo "Reloading systemd configuration..."
                    sudo systemctl daemon-reload
                    # Remove it from known_services so that re-additions are treated as new.
                    unset known_services["$file"]
                    break
                elif [[ "$answer" =~ ^[Nn]$ ]]; then
                    break
                else
                    echo "Invalid response. Please answer y or n."
                fi
            done
        done
    fi

    first_run=false
    sleep 10
done
