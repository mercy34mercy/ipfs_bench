#!/bin/bash

# Script to remove all bandwidth limits by stopping all pumba containers
# Usage: ./remove-bandwidth-limit.sh

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

print_blue "Checking for active Pumba network chaos containers..."

# Find all pumba-rate containers
PUMBA_CONTAINERS=$(docker ps -a --format "{{.Names}}" | grep pumba-rate || true)

if [ -z "$PUMBA_CONTAINERS" ]; then
    print_yellow "No active bandwidth limit containers found"
    exit 0
fi

print_blue "Found bandwidth limit containers:"
echo "$PUMBA_CONTAINERS"
echo ""

# Remove all pumba-rate containers
print_blue "Removing bandwidth limits..."
echo "$PUMBA_CONTAINERS" | xargs docker rm -f

if [ $? -eq 0 ]; then
    print_green "✅ Successfully removed all bandwidth limits"

    # Play notification sound on macOS
    if [[ "$OSTYPE" == "darwin"* ]]; then
        osascript -e 'display notification "All bandwidth limits removed" with title "Pumba Network Chaos" sound name "Glass"'
    fi
else
    print_red "❌ Failed to remove some bandwidth limits"

    # Play error sound on macOS
    if [[ "$OSTYPE" == "darwin"* ]]; then
        osascript -e 'display notification "Failed to remove bandwidth limits" with title "Pumba Network Chaos" sound name "Basso"'
    fi
    exit 1
fi

print_blue "\nCurrent Pumba containers:"
docker ps --format "table {{.Names}}\t{{.Status}}" | grep pumba || echo "None active"
