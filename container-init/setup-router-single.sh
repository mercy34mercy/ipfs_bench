#!/bin/sh
#
# Single Router Traffic Control Setup Script
# Applies bandwidth limits to ALL network interfaces
#

set -e

echo "=========================================="
echo "Single Router TC Setup"
echo "=========================================="

# Install required packages
echo "Installing required packages..."
apk add --no-cache iproute2 iptables

# Load kernel modules (may fail in container, that's OK)
echo "Loading kernel modules..."
modprobe ifb || true

# Get bandwidth settings from environment
BANDWIDTH_RATE=${BANDWIDTH_RATE:-10mbit}

# Calculate appropriate burst and latency based on bandwidth rate
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

echo "Settings:"
echo "  Bandwidth: $BANDWIDTH_RATE"
echo "  Burst: $BURST (auto-calculated)"
echo "  Latency: $LATENCY (fixed minimal)"
echo ""

echo "Configuring iptables for NAT..."
# Enable masquerading for all interfaces
iptables -t nat -A POSTROUTING -j MASQUERADE
echo "✓ iptables NAT configured"
echo ""

echo "Configuring traffic control on all interfaces..."

# Get all ethernet interfaces
INTERFACES=$(ip -o link show | awk -F': ' '{print $2}' | grep '^eth' | cut -d'@' -f1)

IFB_NUM=0
for IFACE in $INTERFACES; do
  echo "  Configuring $IFACE..."

  # Egress (outgoing) traffic control (with auto-calculated burst/latency)
  tc qdisc add dev $IFACE root tbf rate $BANDWIDTH_RATE burst $BURST latency $LATENCY

  # Ingress (incoming) traffic control via IFB
  IFB_DEV="ifb$IFB_NUM"
  ip link add $IFB_DEV type ifb 2>/dev/null || true
  ip link set $IFB_DEV up
  tc qdisc add dev $IFACE handle ffff: ingress
  tc filter add dev $IFACE parent ffff: protocol ip u32 match u32 0 0 action mirred egress redirect dev $IFB_DEV
  tc qdisc add dev $IFB_DEV root tbf rate $BANDWIDTH_RATE burst $BURST latency $LATENCY

  IFB_NUM=$((IFB_NUM + 1))
  echo "  ✓ $IFACE configured (with $IFB_DEV)"
done

echo ""
echo "=========================================="
echo "Router Configuration Complete"
echo "=========================================="
echo "Configured interfaces:"
for IFACE in $INTERFACES; do
  echo "  $IFACE:"
  tc qdisc show dev $IFACE | head -2 | sed 's/^/    /'
done
echo "=========================================="
echo ""
echo "Router is ready! Keeping container alive..."

# Keep container running
tail -f /dev/null
