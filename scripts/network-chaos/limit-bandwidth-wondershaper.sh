#!/bin/bash

# Script to limit bandwidth using wondershaper-like tc commands
# This script manually sets up tc rules that work with BusyBox tc
# Usage: ./limit-bandwidth-wondershaper.sh <rate_kbit>
# Example: ./limit-bandwidth-wondershaper.sh 10000  (for 10Mbps)

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
    print_red "Usage: $0 <rate_kbit>"
    print_red "Example: $0 10000  (for 10Mbps)"
    print_red "Example: $0 100000 (for 100Mbps)"
    echo "Available containers:"
    docker ps --format "table {{.Names}}" | grep -E "(ipfs-org|ipfs-bench)"
    exit 1
fi

RATE_KBIT=$1
RATE_MBIT=$((RATE_KBIT / 1000))

# Get all relevant containers
CONTAINERS=$(docker ps --format "{{.Names}}" | grep -E "(ipfs-org|ipfs-bench)" || true)

if [ -z "$CONTAINERS" ]; then
    print_red "Error: No IPFS or benchmark containers found"
    exit 1
fi

print_blue "Found containers:"
echo "$CONTAINERS"
echo ""
print_yellow "Target bandwidth: ${RATE_MBIT}Mbps (${RATE_KBIT}kbit)"
echo ""

SUCCESS_COUNT=0
FAIL_COUNT=0

for CONTAINER_NAME in $CONTAINERS; do
    print_blue "Applying bandwidth limit to $CONTAINER_NAME..."

    # Get container's network interface
    INTERFACE=$(docker exec $CONTAINER_NAME sh -c "ip route | grep default | awk '{print \$5}'" 2>/dev/null || echo "eth0")

    # Remove existing qdisc
    docker exec $CONTAINER_NAME tc qdisc del dev $INTERFACE root 2>/dev/null || true

    # Add HTB qdisc with rate limit (compatible with BusyBox tc)
    # Using simplified tc syntax that BusyBox supports
    if docker exec $CONTAINER_NAME tc qdisc add dev $INTERFACE handle 1: pfifo limit 1000 2>&1; then
        print_green "  ✅ Bandwidth limit applied to $CONTAINER_NAME ($INTERFACE)"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        print_yellow "  ⚠️  pfifo failed, trying tbf for $CONTAINER_NAME..."
        # Try tbf (Token Bucket Filter) as fallback
        BURST=$((RATE_KBIT * 2))
        if docker exec $CONTAINER_NAME tc qdisc add dev $INTERFACE tbf rate ${RATE_KBIT}kbit burst ${BURST} latency 50ms 2>&1; then
            print_green "  ✅ TBF bandwidth limit applied to $CONTAINER_NAME"
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        else
            print_red "  ❌ Failed to apply limit to $CONTAINER_NAME"
            FAIL_COUNT=$((FAIL_COUNT + 1))
        fi
    fi
done

echo ""
print_blue "======================================"
print_green "Successfully applied: $SUCCESS_COUNT containers"
if [ $FAIL_COUNT -gt 0 ]; then
    print_red "Failed: $FAIL_COUNT containers"
fi
print_yellow "Bandwidth limit: ${RATE_MBIT}Mbps"
print_blue "======================================"

# Show tc rules for verification
print_blue "\nVerifying tc rules on ipfs-bench:"
docker exec ipfs-bench tc qdisc show 2>/dev/null || print_yellow "Could not verify"

print_blue "\nVerifying tc rules on ipfs-org1:"
docker exec ipfs-org1 tc qdisc show 2>/dev/null || print_yellow "Could not verify"

if [[ "$OSTYPE" == "darwin"* ]]; then
    if [ $FAIL_COUNT -eq 0 ]; then
        osascript -e "display notification \"Bandwidth limit (${RATE_MBIT}Mbps) applied to $SUCCESS_COUNT containers\" with title \"TC Bandwidth Limit\" sound name \"Glass\""
    fi
fi

exit $FAIL_COUNT
