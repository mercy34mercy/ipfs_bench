#!/bin/sh
set -e

# ============================================
# Router Pod - Traffic Control Setup
# ============================================
# This script sets up a router container with
# bandwidth limiting using tc (Traffic Control)
# and ifb (Intermediate Functional Block)
#
# This router acts as a gateway for IPFS nodes,
# simulating a home internet connection.
# ============================================

# Bandwidth settings from environment variables
BANDWIDTH_RATE=${BANDWIDTH_RATE:-10mbit}
BANDWIDTH_BURST=${BANDWIDTH_BURST:-32kbit}
BANDWIDTH_LATENCY=${BANDWIDTH_LATENCY:-400ms}
NETWORK_DELAY=${NETWORK_DELAY:-50ms}
PACKET_LOSS=${PACKET_LOSS:-0}

echo "=========================================="
echo "Router Pod - Traffic Control Setup"
echo "=========================================="
echo "Bandwidth Rate: $BANDWIDTH_RATE"
echo "Bandwidth Burst: $BANDWIDTH_BURST"
echo "Network Delay: $NETWORK_DELAY"
echo "Packet Loss: $PACKET_LOSS%"
echo "=========================================="

# ============================================
# Install Required Packages
# ============================================
echo "Installing required packages..."
apk add --no-cache iproute2 iptables

# ============================================
# Enable IP Forwarding
# ============================================
# IP forwarding is enabled via Docker sysctls
echo "IP forwarding (configured via Docker sysctls)..."
echo "  ✓ IP forwarding enabled"

# ============================================
# Find Network Interfaces
# ============================================
echo "Detecting network interfaces..."

# Find interfaces by IP address range
# External interface: 172.30.0.0/16 (internet network)
# Internal interface: 172.31.X.0/24 (org network)

EXT_INTERFACE=$(ip -4 addr show | grep "inet 172.30" | awk '{print $NF}')
INT_INTERFACE=$(ip -4 addr show | grep "inet 172.31" | awk '{print $NF}')

# Fallback to default detection
if [ -z "$EXT_INTERFACE" ]; then
    EXT_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n 1)
fi
if [ -z "$EXT_INTERFACE" ]; then
    EXT_INTERFACE="eth0"
fi

if [ -z "$INT_INTERFACE" ]; then
    INT_INTERFACE=$(ip link show | grep -E "eth[1-9]" | head -n 1 | awk -F: '{print $2}' | tr -d ' ' | cut -d'@' -f1)
fi
if [ -z "$INT_INTERFACE" ]; then
    INT_INTERFACE="$EXT_INTERFACE"
fi

echo "  External interface (internet): $EXT_INTERFACE"
echo "  Internal interface (org network): $INT_INTERFACE"

# ============================================
# Setup NAT (Network Address Translation)
# ============================================
echo "Setting up NAT..."
iptables -t nat -A POSTROUTING -o $EXT_INTERFACE -j MASQUERADE
iptables -A FORWARD -i $INT_INTERFACE -o $EXT_INTERFACE -j ACCEPT
iptables -A FORWARD -i $EXT_INTERFACE -o $INT_INTERFACE -m state --state RELATED,ESTABLISHED -j ACCEPT
echo "  ✓ NAT configured"

# ============================================
# Setup Port Forwarding for IPFS
# ============================================
echo "Setting up port forwarding for IPFS..."

# Detect IPFS node IP address from internal interface
IPFS_NODE_IP=$(ip -4 addr show $INT_INTERFACE | grep inet | awk '{print $2}' | cut -d/ -f1 | sed 's/\.[0-9]*$/.10/')

if [ -n "$IPFS_NODE_IP" ] && [ "$IPFS_NODE_IP" != ".10" ]; then
    echo "  IPFS Node IP: $IPFS_NODE_IP"

    # Get router's external IP address
    ROUTER_IP=$(ip -4 addr show $EXT_INTERFACE | grep inet | awk '{print $2}' | cut -d/ -f1)

    # Forward IPFS API port (5001) - for external connections
    iptables -t nat -A PREROUTING -i $EXT_INTERFACE -p tcp --dport 5001 -j DNAT --to-destination $IPFS_NODE_IP:5001
    iptables -A FORWARD -i $EXT_INTERFACE -o $INT_INTERFACE -p tcp --dport 5001 -d $IPFS_NODE_IP -j ACCEPT

    # Hairpin NAT - for connections from same network (OUTPUT chain)
    iptables -t nat -A OUTPUT -p tcp -d $ROUTER_IP --dport 5001 -j DNAT --to-destination $IPFS_NODE_IP:5001
    # SNAT for hairpin NAT (make reply go back through router)
    iptables -t nat -A POSTROUTING -p tcp -d $IPFS_NODE_IP --dport 5001 -j MASQUERADE
    echo "  ✓ Port 5001 (IPFS API) → $IPFS_NODE_IP:5001 (with Hairpin NAT)"

    # Forward IPFS Gateway port (8080) - for external connections
    iptables -t nat -A PREROUTING -i $EXT_INTERFACE -p tcp --dport 8080 -j DNAT --to-destination $IPFS_NODE_IP:8080
    iptables -A FORWARD -i $EXT_INTERFACE -o $INT_INTERFACE -p tcp --dport 8080 -d $IPFS_NODE_IP -j ACCEPT

    # Hairpin NAT - for connections from same network (OUTPUT chain)
    iptables -t nat -A OUTPUT -p tcp -d $ROUTER_IP --dport 8080 -j DNAT --to-destination $IPFS_NODE_IP:8080
    # SNAT for hairpin NAT (make reply go back through router)
    iptables -t nat -A POSTROUTING -p tcp -d $IPFS_NODE_IP --dport 8080 -j MASQUERADE
    echo "  ✓ Port 8080 (IPFS Gateway) → $IPFS_NODE_IP:8080 (with Hairpin NAT)"
else
    echo "  ⚠ Could not detect IPFS node IP, skipping port forwarding"
fi

# ============================================
# Traffic Control on External Interface
# ============================================
echo "Configuring traffic control on $EXT_INTERFACE..."

# Remove existing qdisc if any
tc qdisc del dev $EXT_INTERFACE root 2>/dev/null || true
tc qdisc del dev $EXT_INTERFACE ingress 2>/dev/null || true

# ============================================
# Egress (Outgoing) Traffic Control
# ============================================
echo "Configuring egress (outgoing) traffic control..."

if [ "$NETWORK_DELAY" = "0ms" ] && [ "$PACKET_LOSS" = "0" ]; then
    # Simple rate limiting without delay or loss
    tc qdisc add dev $EXT_INTERFACE root tbf rate $BANDWIDTH_RATE burst $BANDWIDTH_BURST latency $BANDWIDTH_LATENCY
    echo "  ✓ Egress rate limit: $BANDWIDTH_RATE"
else
    # Rate limiting with delay and/or packet loss
    tc qdisc add dev $EXT_INTERFACE root handle 1: tbf rate $BANDWIDTH_RATE burst $BANDWIDTH_BURST latency $BANDWIDTH_LATENCY

    if [ "$PACKET_LOSS" != "0" ]; then
        tc qdisc add dev $EXT_INTERFACE parent 1:1 handle 10: netem delay $NETWORK_DELAY loss ${PACKET_LOSS}%
        echo "  ✓ Egress: $BANDWIDTH_RATE, delay: $NETWORK_DELAY, loss: $PACKET_LOSS%"
    else
        tc qdisc add dev $EXT_INTERFACE parent 1:1 handle 10: netem delay $NETWORK_DELAY
        echo "  ✓ Egress: $BANDWIDTH_RATE, delay: $NETWORK_DELAY"
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
tc qdisc del dev $IFB_DEVICE root 2>/dev/null || true

# Redirect ingress traffic to ifb0
tc qdisc add dev $EXT_INTERFACE handle ffff: ingress
tc filter add dev $EXT_INTERFACE parent ffff: protocol ip u32 match u32 0 0 \
    action mirred egress redirect dev $IFB_DEVICE

# Apply rate limiting on ifb0
if [ "$NETWORK_DELAY" = "0ms" ] && [ "$PACKET_LOSS" = "0" ]; then
    tc qdisc add dev $IFB_DEVICE root tbf rate $BANDWIDTH_RATE burst $BANDWIDTH_BURST latency $BANDWIDTH_LATENCY
    echo "  ✓ Ingress rate limit: $BANDWIDTH_RATE"
else
    tc qdisc add dev $IFB_DEVICE root handle 1: tbf rate $BANDWIDTH_RATE burst $BANDWIDTH_BURST latency $BANDWIDTH_LATENCY

    if [ "$PACKET_LOSS" != "0" ]; then
        tc qdisc add dev $IFB_DEVICE parent 1:1 handle 10: netem delay $NETWORK_DELAY loss ${PACKET_LOSS}%
        echo "  ✓ Ingress: $BANDWIDTH_RATE, delay: $NETWORK_DELAY, loss: $PACKET_LOSS%"
    else
        tc qdisc add dev $IFB_DEVICE parent 1:1 handle 10: netem delay $NETWORK_DELAY
        echo "  ✓ Ingress: $BANDWIDTH_RATE, delay: $NETWORK_DELAY"
    fi
fi

# ============================================
# Display Configuration
# ============================================
echo ""
echo "=========================================="
echo "Router Configuration Complete"
echo "=========================================="
echo "External Interface ($EXT_INTERFACE):"
tc qdisc show dev $EXT_INTERFACE
echo ""
echo "Ingress via IFB ($IFB_DEVICE):"
tc qdisc show dev $IFB_DEVICE
echo ""
echo "NAT/Firewall Rules:"
iptables -t nat -L POSTROUTING -n -v | head -3
echo "=========================================="
echo ""
echo "Router is ready! Keeping container alive..."

# Keep container running
tail -f /dev/null
