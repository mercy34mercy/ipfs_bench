#!/bin/bash

# Script to add network latency to IPFS containers using Pumba
# Usage: ./add-latency.sh <container-name> <latency>
# Example: ./add-latency.sh ipfs-org1 100ms

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
    print_red "Usage: $0 <container-name> <latency>"
    print_red "Example: $0 ipfs-org1 100ms"
    echo "Available containers:"
    docker ps --format "table {{.Names}}" | grep ipfs-org
    exit 1
fi

CONTAINER_NAME=$1
LATENCY=$2

# Validate container exists
if ! docker ps | grep -q "$CONTAINER_NAME"; then
    print_red "Error: Container '$CONTAINER_NAME' not found or not running"
    echo "Available IPFS containers:"
    docker ps --format "table {{.Names}}" | grep ipfs-org
    exit 1
fi

# Kill any existing Pumba process for this container
print_blue "Stopping any existing network chaos for $CONTAINER_NAME..."
docker ps -a | grep pumba | grep -E "delay.*$CONTAINER_NAME" | awk '{print $1}' | xargs -r docker rm -f 2>/dev/null || true

# Apply latency using Pumba
print_blue "Applying ${LATENCY} latency to $CONTAINER_NAME..."
docker run -d \
    --name "pumba-delay-${CONTAINER_NAME}" \
    --network host \
    -v /var/run/docker.sock:/var/run/docker.sock \
    gaiaadm/pumba:latest \
    netem \
    --duration 1h \
    --tc-image gaiadocker/iproute2 \
    delay \
    --time $LATENCY \
    --jitter 10 \
    --distribution normal \
    $CONTAINER_NAME

if [ $? -eq 0 ]; then
    print_green "✅ Successfully applied ${LATENCY} latency to $CONTAINER_NAME"
    print_yellow "Note: Latency will be applied for 1 hour or until manually stopped"
    print_yellow "To stop: docker rm -f pumba-delay-${CONTAINER_NAME}"
    # Play notification sound on macOS
    if [[ "$OSTYPE" == "darwin"* ]]; then
        osascript -e 'display notification "Network latency applied successfully" with title "Pumba Network Chaos" sound name "Glass"'
    fi
else
    print_red "❌ Failed to apply latency to $CONTAINER_NAME"
    # Play error sound on macOS
    if [[ "$OSTYPE" == "darwin"* ]]; then
        osascript -e 'display notification "Failed to apply network latency" with title "Pumba Network Chaos" sound name "Basso"'
    fi
    exit 1
fi

# Show current Pumba containers
print_blue "Current network chaos containers:"
docker ps | grep pumba | grep -v "pumba  " || echo "None active"