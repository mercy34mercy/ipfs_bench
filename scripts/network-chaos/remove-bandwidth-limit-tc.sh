#!/bin/bash

# Script to remove tc bandwidth limits from all containers
# Usage: ./remove-bandwidth-limit-tc.sh

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

# Get all relevant containers
CONTAINERS=$(docker ps --format "{{.Names}}" | grep -E "(ipfs-org|ipfs-bench)" || true)

if [ -z "$CONTAINERS" ]; then
    print_red "Error: No IPFS or benchmark containers found"
    exit 1
fi

print_blue "Removing bandwidth limits from containers..."
echo ""

SUCCESS_COUNT=0
FAIL_COUNT=0

for CONTAINER_NAME in $CONTAINERS; do
    print_blue "Removing tc rules from $CONTAINER_NAME..."

    # Get container's network interface
    INTERFACE=$(docker exec $CONTAINER_NAME sh -c "ip route | grep default | awk '{print \$5}'" 2>/dev/null || echo "eth0")

    # Remove tc rules
    if docker exec $CONTAINER_NAME tc qdisc del dev $INTERFACE root 2>/dev/null; then
        print_green "  ✅ Removed limits from $CONTAINER_NAME"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        print_blue "  ℹ️  No limits to remove from $CONTAINER_NAME"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    fi
done

echo ""
print_blue "======================================"
print_green "Successfully cleaned: $SUCCESS_COUNT containers"
print_blue "======================================"

exit 0
