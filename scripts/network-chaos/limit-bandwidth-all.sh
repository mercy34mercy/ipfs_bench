#!/bin/bash

# Script to limit bandwidth for ALL containers using pumba with tc-image
# This ensures that the benchmark client is also subject to bandwidth restrictions
# Usage: ./limit-bandwidth-all.sh <rate>
# Example: ./limit-bandwidth-all.sh 10mbit

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
if [ $# -lt 1 ]; then
    print_red "Usage: $0 <rate>"
    print_red "Example: $0 10mbit"
    print_red "Rate examples: 100kbit, 1mbit, 10mbit, 100mbit, 1gbit"
    echo "Available containers:"
    docker ps --format "table {{.Names}}" | grep -E "(ipfs-org|ipfs-bench)"
    exit 1
fi

RATE=$1

# Get all relevant containers (ipfs-org* and ipfs-bench)
CONTAINERS=$(docker ps --format "{{.Names}}" | grep -E "(ipfs-org|ipfs-bench)" || true)

if [ -z "$CONTAINERS" ]; then
    print_red "Error: No IPFS or benchmark containers found"
    exit 1
fi

print_blue "Found containers:"
echo "$CONTAINERS"
echo ""

# Kill any existing Pumba processes
print_blue "Stopping any existing pumba containers..."
docker ps -a | grep pumba-rate | awk '{print $1}' | xargs docker rm -f 2>/dev/null || true

# Apply bandwidth limit to each container using pumba
SUCCESS_COUNT=0
FAIL_COUNT=0

for CONTAINER_NAME in $CONTAINERS; do
    print_blue "Limiting bandwidth to ${RATE} for $CONTAINER_NAME..."

    if docker run -d \
        --name "pumba-rate-${CONTAINER_NAME}" \
        -v /var/run/docker.sock:/var/run/docker.sock \
        gaiaadm/pumba:latest \
        netem \
        --tc-image ghcr.io/alexei-led/pumba-alpine-nettools:latest \
        --duration 24h \
        rate \
        --rate ${RATE} \
        $CONTAINER_NAME > /dev/null 2>&1; then

        print_green "  ✅ Successfully limited $CONTAINER_NAME"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        print_red "  ❌ Failed to limit $CONTAINER_NAME"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
done

echo ""
print_blue "======================================"
print_green "Successfully applied: $SUCCESS_COUNT containers"
if [ $FAIL_COUNT -gt 0 ]; then
    print_red "Failed: $FAIL_COUNT containers"
fi
print_yellow "Bandwidth limit: ${RATE}"
print_yellow "Method: pumba netem rate (with tc-image)"
print_yellow "Duration: 24 hours or until manually stopped"
print_yellow "To stop all: docker ps | grep pumba-rate | awk '{print \$1}' | xargs docker rm -f"
print_blue "======================================"

# Show current Pumba containers
print_blue "\nActive pumba containers:"
docker ps --format "table {{.Names}}\t{{.Status}}" | grep pumba-rate || echo "None active"

# Play notification sound on macOS
if [[ "$OSTYPE" == "darwin"* ]]; then
    if [ $FAIL_COUNT -eq 0 ]; then
        osascript -e "display notification \"Bandwidth limit ($RATE) applied to $SUCCESS_COUNT containers\" with title \"TC Bandwidth Limit\" sound name \"Glass\""
    else
        osascript -e "display notification \"Applied to $SUCCESS_COUNT containers, $FAIL_COUNT failed\" with title \"TC Bandwidth Limit\" sound name \"Basso\""
    fi
fi

exit $FAIL_COUNT
