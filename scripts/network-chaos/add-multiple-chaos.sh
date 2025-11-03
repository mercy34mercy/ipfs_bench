#!/bin/bash

# Script to apply multiple network impairments to IPFS containers using Pumba
# Usage: ./add-multiple-chaos.sh <container-name> <latency> <loss%> [jitter]
# Example: ./add-multiple-chaos.sh ipfs-org1 100ms 5 20ms

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
if [ $# -lt 3 ]; then
    print_red "Usage: $0 <container-name> <latency> <loss%> [jitter]"
    print_red "Example: $0 ipfs-org1 100ms 5 20ms"
    echo "Available containers:"
    docker ps --format "table {{.Names}}" | grep ipfs-org
    exit 1
fi

CONTAINER_NAME=$1
LATENCY=$2
LOSS_PERCENT=$3
JITTER=${4:-"10ms"}  # Default jitter of 10ms if not specified

# Validate container exists
if ! docker ps | grep -q "$CONTAINER_NAME"; then
    print_red "Error: Container '$CONTAINER_NAME' not found or not running"
    echo "Available IPFS containers:"
    docker ps --format "table {{.Names}}" | grep ipfs-org
    exit 1
fi

# Validate loss percentage
if ! [[ "$LOSS_PERCENT" =~ ^[0-9]+$ ]] || [ "$LOSS_PERCENT" -lt 0 ] || [ "$LOSS_PERCENT" -gt 100 ]; then
    print_red "Error: Loss percentage must be a number between 0 and 100"
    exit 1
fi

# Kill any existing Pumba process for this container
print_blue "Stopping any existing network chaos for $CONTAINER_NAME..."
docker ps -a | grep pumba | grep -E "multi.*$CONTAINER_NAME" | awk '{print $1}' | xargs -r docker rm -f 2>/dev/null || true

# Apply multiple impairments using Pumba
print_blue "Applying multiple network impairments to $CONTAINER_NAME..."
print_blue "  - Latency: ${LATENCY}"
print_blue "  - Jitter: ${JITTER}"
print_blue "  - Packet loss: ${LOSS_PERCENT}%"

docker run -d \
    --name "pumba-multi-${CONTAINER_NAME}" \
    --network host \
    -v /var/run/docker.sock:/var/run/docker.sock \
    gaiaadm/pumba:latest \
    netem \
    --duration 1h \
    --tc-image gaiadocker/iproute2 \
    delay \
    --time $LATENCY \
    --jitter $JITTER \
    --distribution normal \
    loss \
    --percent ${LOSS_PERCENT} \
    $CONTAINER_NAME

if [ $? -eq 0 ]; then
    print_green "✅ Successfully applied network impairments to $CONTAINER_NAME:"
    print_green "   - Latency: ${LATENCY}"
    print_green "   - Jitter: ${JITTER}"
    print_green "   - Packet loss: ${LOSS_PERCENT}%"
    print_yellow "Note: Network impairments will be applied for 1 hour or until manually stopped"
    print_yellow "To stop: docker rm -f pumba-multi-${CONTAINER_NAME}"
    # Play notification sound on macOS
    if [[ "$OSTYPE" == "darwin"* ]]; then
        osascript -e 'display notification "Multiple network impairments applied successfully" with title "Pumba Network Chaos" sound name "Glass"'
    fi
else
    print_red "❌ Failed to apply network impairments to $CONTAINER_NAME"
    # Play error sound on macOS
    if [[ "$OSTYPE" == "darwin"* ]]; then
        osascript -e 'display notification "Failed to apply network impairments" with title "Pumba Network Chaos" sound name "Basso"'
    fi
    exit 1
fi

# Show current Pumba containers
print_blue "Current network chaos containers:"
docker ps | grep pumba | grep -v "pumba  " || echo "None active"