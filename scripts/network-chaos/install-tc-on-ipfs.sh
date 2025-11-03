#!/bin/bash

# Script to install full iproute2 on IPFS containers
# This replaces BusyBox tc with full-featured tc
# Usage: ./install-tc-on-ipfs.sh

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

# Get all IPFS org containers
CONTAINERS=$(docker ps --format "{{.Names}}" | grep "ipfs-org" || true)

if [ -z "$CONTAINERS" ]; then
    print_red "Error: No IPFS containers found"
    exit 1
fi

print_blue "Installing iproute2 on IPFS containers..."
echo ""

SUCCESS_COUNT=0
FAIL_COUNT=0

for CONTAINER_NAME in $CONTAINERS; do
    print_blue "Installing iproute2 on $CONTAINER_NAME..."

    # Try to install iproute2
    if docker exec $CONTAINER_NAME sh -c "apk add --no-cache iproute2 2>/dev/null" > /dev/null 2>&1; then
        # Verify tc is now available
        if docker exec $CONTAINER_NAME which tc > /dev/null 2>&1; then
            TC_VERSION=$(docker exec $CONTAINER_NAME tc -Version 2>&1 | head -1)
            print_green "  ✅ Installed on $CONTAINER_NAME ($TC_VERSION)"
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        else
            print_red "  ❌ Installation failed on $CONTAINER_NAME"
            FAIL_COUNT=$((FAIL_COUNT + 1))
        fi
    else
        print_red "  ❌ apk install failed on $CONTAINER_NAME"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
done

echo ""
print_blue "======================================"
print_green "Successfully installed: $SUCCESS_COUNT containers"
if [ $FAIL_COUNT -gt 0 ]; then
    print_red "Failed: $FAIL_COUNT containers"
fi
print_blue "======================================"

# Play notification sound on macOS
if [[ "$OSTYPE" == "darwin"* ]]; then
    if [ $FAIL_COUNT -eq 0 ]; then
        osascript -e "display notification \"iproute2 installed on $SUCCESS_COUNT containers\" with title \"TC Installation\" sound name \"Glass\""
    fi
fi

exit $FAIL_COUNT
