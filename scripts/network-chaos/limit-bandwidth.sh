#!/bin/bash

# Script to limit bandwidth for IPFS containers using Pumba
# Usage: ./limit-bandwidth.sh <container-name> <rate>
# Example: ./limit-bandwidth.sh ipfs-org1 1mbit

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

# Check parameters
if [ $# -lt 2 ]; then
    print_red "Usage: $0 <container-name> <rate>"
    print_red "Example: $0 ipfs-org1 1mbit"
    print_red "Rate examples: 100kbit, 1mbit, 10mbit, 100mbit"
    echo "Available containers:"
    docker ps --format "table {{.Names}}" | grep ipfs-org
    exit 1
fi

CONTAINER_NAME=$1
RATE=$2

# Validate container exists
if ! docker ps | grep -q "$CONTAINER_NAME"; then
    print_red "Error: Container '$CONTAINER_NAME' not found or not running"
    echo "Available IPFS containers:"
    docker ps --format "table {{.Names}}" | grep ipfs-org
    exit 1
fi

# Kill any existing Pumba process for this container
print_blue "Stopping any existing network chaos for $CONTAINER_NAME..."
docker ps -a | grep pumba | grep -E "rate.*$CONTAINER_NAME" | awk '{print $1}' | xargs -r docker rm -f 2>/dev/null || true

# Apply bandwidth limit using Pumba
print_blue "Limiting bandwidth to ${RATE} for $CONTAINER_NAME..."
docker run -d \
    --name "pumba-rate-${CONTAINER_NAME}" \
    -v /var/run/docker.sock:/var/run/docker.sock \
    gaiaadm/pumba:latest \
    netem \
    --duration 24h \
    rate \
    --rate ${RATE} \
    $CONTAINER_NAME

if [ $? -eq 0 ]; then
    print_green "✅ Successfully limited bandwidth to ${RATE} for $CONTAINER_NAME"
    print_yellow "Note: Bandwidth limit will be applied for 1 hour or until manually stopped"
    print_yellow "To stop: docker rm -f pumba-rate-${CONTAINER_NAME}"
    # Play notification sound on macOS
    if [[ "$OSTYPE" == "darwin"* ]]; then
        osascript -e 'display notification "Bandwidth limit applied successfully" with title "Pumba Network Chaos" sound name "Glass"'
    fi
else
    print_red "❌ Failed to limit bandwidth for $CONTAINER_NAME"
    # Play error sound on macOS
    if [[ "$OSTYPE" == "darwin"* ]]; then
        osascript -e 'display notification "Failed to limit bandwidth" with title "Pumba Network Chaos" sound name "Basso"'
    fi
    exit 1
fi

# Show current Pumba containers
print_blue "Current network chaos containers:"
docker ps | grep pumba | grep -v "pumba  " || echo "None active"