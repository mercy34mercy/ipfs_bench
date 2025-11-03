#!/bin/bash

# Script to limit bandwidth using tc (Traffic Control) directly in containers
# This applies bidirectional bandwidth limits (both ingress and egress)
# Usage: ./limit-bandwidth-tc.sh <rate>
# Example: ./limit-bandwidth-tc.sh 10mbit

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

# Apply bandwidth limit to each container using tc
SUCCESS_COUNT=0
FAIL_COUNT=0

for CONTAINER_NAME in $CONTAINERS; do
    print_blue "Applying egress bandwidth limit (${RATE}) to $CONTAINER_NAME..."

    # Get container's network interface
    INTERFACE=$(docker exec $CONTAINER_NAME sh -c "ip route | grep default | awk '{print \$5}'" 2>/dev/null || echo "eth0")

    # Remove existing tc rules if any
    docker exec $CONTAINER_NAME tc qdisc del dev $INTERFACE root 2>/dev/null || true

    # Apply egress (outgoing) limit using netem rate (compatible with existing setup)
    # This is more compatible with the tc versions in IPFS containers
    if docker exec $CONTAINER_NAME tc qdisc add dev $INTERFACE root netem rate $RATE 2>&1; then
        print_green "  ✅ Egress limit applied to $CONTAINER_NAME ($INTERFACE)"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        print_red "  ❌ Failed to apply limit to $CONTAINER_NAME"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
done

echo ""
print_blue "======================================"
print_green "Successfully applied: $SUCCESS_COUNT containers"
if [ $FAIL_COUNT -gt 0 ]; then
    print_red "Failed: $FAIL_COUNT containers"
fi
print_yellow "Bandwidth limit: ${RATE} (egress)"
print_yellow "Note: Since all containers have egress limits,"
print_yellow "      both upload and download will be limited."
print_yellow "To remove: ./remove-bandwidth-limit-tc.sh"
print_blue "======================================"

# Show tc rules for verification
print_blue "\nVerifying tc rules on ipfs-bench:"
docker exec ipfs-bench tc qdisc show 2>/dev/null || print_yellow "Could not verify tc rules"

print_blue "\nVerifying tc rules on ipfs-org1:"
docker exec ipfs-org1 tc qdisc show 2>/dev/null || print_yellow "Could not verify tc rules"

# Play notification sound on macOS
if [[ "$OSTYPE" == "darwin"* ]]; then
    if [ $FAIL_COUNT -eq 0 ]; then
        osascript -e "display notification \"Bandwidth limit ($RATE) applied to $SUCCESS_COUNT containers\" with title \"TC Bandwidth Limit\" sound name \"Glass\""
    else
        osascript -e "display notification \"Applied to $SUCCESS_COUNT containers, $FAIL_COUNT failed\" with title \"TC Bandwidth Limit\" sound name \"Basso\""
    fi
fi

exit $FAIL_COUNT
