#!/bin/sh
set -e

# ============================================
# Private IPFS Node with Traffic Control
# ============================================
# This script initializes a private IPFS node
# with bandwidth limiting using tc (Traffic Control)
# and ifb (Intermediate Functional Block)
# ============================================

CONFIG_PATH=${IPFS_PATH:-/data/ipfs}/config

# Bandwidth settings from environment variables
BANDWIDTH_RATE=${BANDWIDTH_RATE:-10mbit}
BANDWIDTH_BURST=${BANDWIDTH_BURST:-32kbit}
BANDWIDTH_LATENCY=${BANDWIDTH_LATENCY:-400ms}
DELAY=${NETWORK_DELAY:-0ms}
PACKET_LOSS=${PACKET_LOSS:-0}

echo "=========================================="
echo "Starting Private IPFS Node with TC"
echo "=========================================="
echo "Bandwidth Rate: $BANDWIDTH_RATE"
echo "Bandwidth Burst: $BANDWIDTH_BURST"
echo "Network Delay: $DELAY"
echo "Packet Loss: $PACKET_LOSS%"
echo "=========================================="

# ============================================
# Install Required Packages
# ============================================
echo "Installing required packages..."
apk add --no-cache iproute2 kmod 2>/dev/null || {
    echo "Warning: Could not install packages. TC functionality may not work."
}

# ============================================
# IPFS Initialization
# ============================================
if [ ! -f "$CONFIG_PATH" ]; then
  echo "Initializing IPFS..."
  ipfs init
  ipfs bootstrap rm --all
fi

# Private network hardening for recent Kubo versions
echo "Configuring private network..."
ipfs config --json AutoConf.Enabled false >/dev/null
ipfs config --json DNS.Resolvers '{}' >/dev/null
ipfs config --json Routing.DelegatedRouters '[]' >/dev/null
ipfs config --json Ipns.DelegatedPublishers '[]' >/dev/null
ipfs config Routing.Type dht >/dev/null
ipfs config --json AutoTLS.Enabled false >/dev/null
ipfs config Addresses.API /ip4/0.0.0.0/tcp/5001 >/dev/null
ipfs config Addresses.Gateway /ip4/0.0.0.0/tcp/8080 >/dev/null

cp /container-init/swarm.key /data/ipfs/swarm.key
chmod 600 /data/ipfs/swarm.key

# ============================================
# Traffic Control Setup
# ============================================
echo "Setting up Traffic Control..."

# Find the network interface (usually eth0)
INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n 1)
if [ -z "$INTERFACE" ]; then
    INTERFACE="eth0"
fi
echo "Network interface: $INTERFACE"

# ============================================
# Egress (Outgoing) Traffic Control
# ============================================
echo "Configuring egress (outgoing) traffic control..."

# Remove existing qdisc if any
tc qdisc del dev $INTERFACE root 2>/dev/null || true

# Add TBF (Token Bucket Filter) for rate limiting
if [ "$DELAY" = "0ms" ] && [ "$PACKET_LOSS" = "0" ]; then
    # Simple rate limiting without delay or loss
    tc qdisc add dev $INTERFACE root tbf rate $BANDWIDTH_RATE burst $BANDWIDTH_BURST latency $BANDWIDTH_LATENCY
    echo "  ✓ Egress rate limit: $BANDWIDTH_RATE"
else
    # Rate limiting with delay and/or packet loss
    tc qdisc add dev $INTERFACE root handle 1: tbf rate $BANDWIDTH_RATE burst $BANDWIDTH_BURST latency $BANDWIDTH_LATENCY

    # Add netem for delay and packet loss
    if [ "$PACKET_LOSS" != "0" ]; then
        tc qdisc add dev $INTERFACE parent 1:1 handle 10: netem delay $DELAY loss ${PACKET_LOSS}%
        echo "  ✓ Egress rate limit: $BANDWIDTH_RATE, delay: $DELAY, loss: $PACKET_LOSS%"
    else
        tc qdisc add dev $INTERFACE parent 1:1 handle 10: netem delay $DELAY
        echo "  ✓ Egress rate limit: $BANDWIDTH_RATE, delay: $DELAY"
    fi
fi

# ============================================
# Ingress (Incoming) Traffic Control with IFB
# ============================================
echo "Configuring ingress (incoming) traffic control..."

# Load ifb module
modprobe ifb numifbs=1 2>/dev/null || echo "  ⚠ ifb module already loaded or not available"

# Setup ifb0 device
IFB_DEVICE="ifb0"
ip link add $IFB_DEVICE type ifb 2>/dev/null || echo "  ⚠ $IFB_DEVICE already exists"
ip link set $IFB_DEVICE up

# Remove existing ingress qdisc if any
tc qdisc del dev $INTERFACE ingress 2>/dev/null || true
tc qdisc del dev $IFB_DEVICE root 2>/dev/null || true

# Redirect ingress traffic to ifb0
tc qdisc add dev $INTERFACE handle ffff: ingress
tc filter add dev $INTERFACE parent ffff: protocol ip u32 match u32 0 0 \
    action mirred egress redirect dev $IFB_DEVICE

# Apply rate limiting on ifb0 (which handles the redirected ingress traffic)
if [ "$DELAY" = "0ms" ] && [ "$PACKET_LOSS" = "0" ]; then
    # Simple rate limiting without delay or loss
    tc qdisc add dev $IFB_DEVICE root tbf rate $BANDWIDTH_RATE burst $BANDWIDTH_BURST latency $BANDWIDTH_LATENCY
    echo "  ✓ Ingress rate limit: $BANDWIDTH_RATE"
else
    # Rate limiting with delay and/or packet loss
    tc qdisc add dev $IFB_DEVICE root handle 1: tbf rate $BANDWIDTH_RATE burst $BANDWIDTH_BURST latency $BANDWIDTH_LATENCY

    if [ "$PACKET_LOSS" != "0" ]; then
        tc qdisc add dev $IFB_DEVICE parent 1:1 handle 10: netem delay $DELAY loss ${PACKET_LOSS}%
        echo "  ✓ Ingress rate limit: $BANDWIDTH_RATE, delay: $DELAY, loss: $PACKET_LOSS%"
    else
        tc qdisc add dev $IFB_DEVICE parent 1:1 handle 10: netem delay $DELAY
        echo "  ✓ Ingress rate limit: $BANDWIDTH_RATE, delay: $DELAY"
    fi
fi

# ============================================
# Display Configuration
# ============================================
echo ""
echo "=========================================="
echo "Traffic Control Configuration Complete"
echo "=========================================="
echo "Egress ($INTERFACE):"
tc qdisc show dev $INTERFACE
echo ""
echo "Ingress ($IFB_DEVICE):"
tc qdisc show dev $IFB_DEVICE
echo "=========================================="
echo ""

# ============================================
# Start IPFS Daemon
# ============================================
echo "Starting IPFS daemon..."
exec ipfs daemon --migrate=true --enable-gc
