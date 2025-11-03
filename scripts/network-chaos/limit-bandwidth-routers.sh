#!/bin/bash

# ============================================
# Router Pod - Dynamic Bandwidth Changer
# ============================================
# This script changes the bandwidth limit
# on all router containers dynamically.
#
# Usage: ./limit-bandwidth-routers.sh <rate>
# Example: ./limit-bandwidth-routers.sh 10mbit
# ============================================

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
    echo ""
    echo "Available router containers:"
    docker ps --format "table {{.Names}}" | grep router || echo "No router containers found"
    exit 1
fi

BANDWIDTH_RATE=$1

# Get all router containers (supports both "router" and "router-*" patterns)
ROUTERS=$(docker ps --format "{{.Names}}" | grep -E "^router-|^router$" || true)

if [ -z "$ROUTERS" ]; then
    print_red "Error: No router containers found"
    print_yellow "Make sure Router Pod network is running:"
    print_yellow "  make up-router (for single router)"
    print_yellow "  or docker-compose up -d (for router pod)"
    exit 1
fi

print_blue "Found router containers:"
echo "$ROUTERS"
echo ""

SUCCESS_COUNT=0
FAIL_COUNT=0

# Function to update TC settings on a router
update_router_tc() {
    local ROUTER=$1
    local RATE=$2

    print_blue "Updating bandwidth to ${RATE} for $ROUTER..."

    # Create temporary script to update TC settings
    cat > /tmp/update-tc-${ROUTER}.sh << 'EOFSCRIPT'
#!/bin/sh
set -e

BANDWIDTH_RATE="$1"
ROUTER_NAME="$2"

# Calculate appropriate burst and latency based on bandwidth rate
# Extract numeric value and unit from rate (e.g., "1000mbit" -> 1000)
RATE_VALUE=$(echo "$BANDWIDTH_RATE" | grep -oE '[0-9]+')
RATE_UNIT=$(echo "$BANDWIDTH_RATE" | grep -oE '[a-z]+')

# Convert to Mbps for comparison
case "$RATE_UNIT" in
    gbit) RATE_MBPS=$((RATE_VALUE * 1000)) ;;
    mbit) RATE_MBPS=$RATE_VALUE ;;
    kbit) RATE_MBPS=$((RATE_VALUE / 1000)) ;;
    *) RATE_MBPS=$RATE_VALUE ;;
esac

# Set burst based on bandwidth (latency fixed to 1ms for minimal delay)
if [ $RATE_MBPS -ge 1000 ]; then
    # 1Gbps or higher
    BURST="100mbit"
elif [ $RATE_MBPS -ge 100 ]; then
    # 100Mbps to 1Gbps
    BURST="10mbit"
elif [ $RATE_MBPS -ge 10 ]; then
    # 10Mbps to 100Mbps
    BURST="1mbit"
else
    # Less than 10Mbps
    BURST="100kbit"
fi

LATENCY="1ms"
echo "Calculated: burst=$BURST, latency=$LATENCY (fixed minimal)"

# Determine interfaces to update
# For Single Router ("router"), update all ethernet interfaces
# For Router Pod ("router-orgX"), update only the external interface
if [ "$ROUTER_NAME" = "router" ]; then
    # Single Router: get all ethernet interfaces
    INTERFACES=$(ip -o link show | awk -F': ' '{print $2}' | grep '^eth' | cut -d'@' -f1)
    echo "Single Router mode: Updating all interfaces"
else
    # Router Pod: find external interface only
    EXT_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n 1)
    if [ -z "$EXT_INTERFACE" ]; then
        EXT_INTERFACE="eth0"
    fi
    INTERFACES="$EXT_INTERFACE"
    echo "Router Pod mode: Updating interface: $EXT_INTERFACE"
fi

# Apply TC settings to each interface
IFB_NUM=0
for IFACE in $INTERFACES; do
    echo "  Configuring $IFACE..."

    # Remove existing qdisc
    tc qdisc del dev $IFACE root 2>/dev/null || true
    tc qdisc del dev $IFACE ingress 2>/dev/null || true

    # Re-add egress TC (with calculated burst/latency)
    tc qdisc add dev $IFACE root tbf rate $BANDWIDTH_RATE burst $BURST latency $LATENCY
    echo "    ✓ Egress: $BANDWIDTH_RATE (burst=$BURST, lat=$LATENCY)"

    # Re-add ingress TC (using IFB device)
    IFB_DEV="ifb$IFB_NUM"
    ip link add $IFB_DEV type ifb 2>/dev/null || true
    ip link set $IFB_DEV up
    tc qdisc del dev $IFB_DEV root 2>/dev/null || true

    tc qdisc add dev $IFACE handle ffff: ingress
    tc filter add dev $IFACE parent ffff: protocol ip u32 match u32 0 0 \
        action mirred egress redirect dev $IFB_DEV

    # Re-add ingress TC (with calculated burst/latency)
    tc qdisc add dev $IFB_DEV root tbf rate $BANDWIDTH_RATE burst $BURST latency $LATENCY
    echo "    ✓ Ingress: $BANDWIDTH_RATE (via $IFB_DEV, burst=$BURST, lat=$LATENCY)"

    IFB_NUM=$((IFB_NUM + 1))
done

echo "TC update complete"
EOFSCRIPT

    # Copy script to router container and execute
    if docker cp /tmp/update-tc-${ROUTER}.sh ${ROUTER}:/tmp/update-tc.sh 2>/dev/null && \
       docker exec ${ROUTER} sh /tmp/update-tc.sh \
           "$BANDWIDTH_RATE" \
           "$ROUTER" 2>&1 | grep -v "^$"; then
        print_green "  ✅ Successfully updated $ROUTER"
        rm -f /tmp/update-tc-${ROUTER}.sh
        return 0
    else
        print_red "  ❌ Failed to update $ROUTER"
        rm -f /tmp/update-tc-${ROUTER}.sh
        return 1
    fi
}

# Update all routers
for ROUTER in $ROUTERS; do
    if update_router_tc "$ROUTER" "$BANDWIDTH_RATE"; then
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
    echo ""
done

echo ""
print_blue "======================================"
print_green "Successfully updated: $SUCCESS_COUNT routers"
if [ $FAIL_COUNT -gt 0 ]; then
    print_red "Failed: $FAIL_COUNT routers"
fi
print_yellow "Bandwidth limit: ${BANDWIDTH_RATE}"
print_yellow "Burst: auto-calculated, Latency: 1ms (fixed)"
print_blue "======================================"

# Verify settings on first router
FIRST_ROUTER=$(echo "$ROUTERS" | head -n 1)
print_blue "\nVerifying settings on $FIRST_ROUTER:"
docker exec $FIRST_ROUTER sh -c "echo 'Egress (first interface):' && tc qdisc show | head -3"
echo ""
docker exec $FIRST_ROUTER sh -c "echo 'Ingress (ifb0):' && tc qdisc show dev ifb0 | head -3" 2>/dev/null || true

# Play notification sound on macOS
if [[ "$OSTYPE" == "darwin"* ]]; then
    if [ $FAIL_COUNT -eq 0 ]; then
        osascript -e "display notification \"Bandwidth limit ($BANDWIDTH_RATE) applied to $SUCCESS_COUNT routers\" with title \"Router Pod Bandwidth Update\" sound name \"Glass\"" 2>/dev/null || true
    else
        osascript -e "display notification \"Updated $SUCCESS_COUNT routers, $FAIL_COUNT failed\" with title \"Router Pod Bandwidth Update\" sound name \"Basso\"" 2>/dev/null || true
    fi
fi

exit $FAIL_COUNT
