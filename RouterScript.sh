# RouterOS script to set IP addresses on two interfaces

# Define variables for interfaces and IP addresses
:local interface1 "ether5"
:local interface2 "ether6"
:local ip1 "172.20.154.1/16"
:local ip2 "192.168.154.1/24"

# Log start of script
:log info "Starting IP address configuration script"

# Check if IP exists on interface1 and remove it if it does
:if ([:len [/ip address find interface=$interface1]] > 0) do={
    :log info "Removing existing IP from $interface1"
    /ip address remove [/ip address find interface=$interface1]
}

# Check if IP exists on interface2 and remove it if it does
:if ([:len [/ip address find interface=$interface2]] > 0) do={
    :log info "Removing existing IP from $interface2"
    /ip address remove [/ip address find interface=$interface2]
}

# Add new IP addresses to interfaces
:log info "Setting $ip1 on $interface1"
/ip address add address=$ip1 interface=$interface1

:log info "Setting $ip2 on $interface2"
/ip address add address=$ip2 interface=$interface2

# Verify the configuration
:delay 2s
:local ip1Check [/ip address get [find interface=$interface1] address]
:local ip2Check [/ip address get [find interface=$interface2] address]

:if ($ip1Check = $ip1) do={
    :log info "$interface1 successfully set to $ip1"
} else={
    :log error "Failed to set $ip1 on $interface1. Current IP: $ip1Check"
}

:if ($ip2Check = $ip2) do={
    :log info "$interface2 successfully set to $ip2"
} else={
    :log error "Failed to set $ip2 on $interface2. Current IP: $ip2Check"
}

:log info "IP configuration script completed"