#!/bin/bash

# Script to stop all network chaos for a container or all containers
# Usage: ./stop-chaos.sh [container-name]
# Example: ./stop-chaos.sh ipfs-org1  (stops chaos for specific container)
#          ./stop-chaos.sh             (stops all chaos)

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

# Check if specific container is specified
if [ $# -eq 0 ]; then
    # Stop all chaos
    print_blue "Stopping all network chaos..."
    PUMBA_CONTAINERS=$(docker ps -a | grep pumba | grep -v "pumba  " | awk '{print $1}')

    if [ -z "$PUMBA_CONTAINERS" ]; then
        print_yellow "No active network chaos found"
    else
        echo "$PUMBA_CONTAINERS" | xargs -r docker rm -f
        print_green "✅ Stopped all network chaos"
        # Play notification sound on macOS
        if [[ "$OSTYPE" == "darwin"* ]]; then
            osascript -e 'display notification "All network chaos stopped" with title "Pumba Network Chaos" sound name "Glass"'
        fi
    fi
else
    # Stop chaos for specific container
    CONTAINER_NAME=$1
    print_blue "Stopping network chaos for $CONTAINER_NAME..."

    PUMBA_CONTAINERS=$(docker ps -a | grep pumba | grep -E "(delay|loss|rate|corrupt).*$CONTAINER_NAME" | awk '{print $1}')

    if [ -z "$PUMBA_CONTAINERS" ]; then
        print_yellow "No active network chaos found for $CONTAINER_NAME"
    else
        echo "$PUMBA_CONTAINERS" | xargs -r docker rm -f
        print_green "✅ Stopped network chaos for $CONTAINER_NAME"
        # Play notification sound on macOS
        if [[ "$OSTYPE" == "darwin"* ]]; then
            osascript -e "display notification \"Network chaos stopped for $CONTAINER_NAME\" with title \"Pumba Network Chaos\" sound name \"Glass\""
        fi
    fi
fi

# Show remaining Pumba containers
print_blue "Current network chaos containers:"
docker ps | grep pumba | grep -v "pumba  " || echo "None active"