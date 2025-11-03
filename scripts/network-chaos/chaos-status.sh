#!/bin/bash

# Script to show the status of all network chaos
# Usage: ./chaos-status.sh

set -e

# Color output functions
print_blue() {
    echo -e "\033[0;34m${1}\033[0m"
}

print_green() {
    echo -e "\033[0;32m${1}\033[0m"
}

print_red() {
    echo -e "\033[0;31m${1}\033[0m"
}

print_yellow() {
    echo -e "\033[0;33m${1}\033[0m"
}

print_blue "===================== Network Chaos Status ====================="

# Check if any Pumba containers are running
PUMBA_CONTAINERS=$(docker ps | grep pumba | grep -v "pumba  " || true)

if [ -z "$PUMBA_CONTAINERS" ]; then
    print_yellow "No active network chaos found"
    echo ""
    echo "Available IPFS containers for chaos testing:"
    docker ps --format "table {{.Names}}\t{{.Status}}" | grep ipfs-org || echo "No IPFS containers running"
else
    print_green "Active Network Chaos:"
    echo ""

    # Show detailed info for each Pumba container
    docker ps --format "table {{.Names}}\t{{.Command}}\t{{.Status}}" | grep pumba | grep -v "pumba  "
    echo ""

    print_blue "Affected containers:"
    for pumba in $(docker ps --format "{{.Names}}" | grep pumba | grep -v "^pumba$"); do
        # Extract the container name from pumba container name
        if [[ $pumba =~ pumba-[^-]+-(.+)$ ]]; then
            container="${BASH_REMATCH[1]}"
            chaos_type=$(echo $pumba | cut -d'-' -f2)
            echo "  - $container: $chaos_type chaos applied"
        fi
    done
fi

echo ""
print_blue "Available commands:"
echo "  ./add-latency.sh <container> <latency>        - Add network latency"
echo "  ./add-packet-loss.sh <container> <loss%>      - Add packet loss"
echo "  ./limit-bandwidth.sh <container> <rate>       - Limit bandwidth"
echo "  ./add-multiple-chaos.sh <container> <latency> <loss%> [jitter]  - Apply multiple impairments"
echo "  ./stop-chaos.sh [container]                   - Stop chaos (all or specific)"
echo ""
print_blue "================================================================="