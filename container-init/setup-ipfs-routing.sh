#!/bin/sh
#
# IPFS node routing setup
# Route all traffic through the router
#

set -e

echo "Setting up routing for IPFS node..."

# Detect the router IP on this network
# Router is always .2 on each org network
NETWORK_PREFIX=$(ip -4 addr show eth0 | grep inet | awk '{print $2}' | cut -d'/' -f1 | sed 's/\.[0-9]*$//')
ROUTER_IP="${NETWORK_PREFIX}.2"

echo "  Network: ${NETWORK_PREFIX}.0/24"
echo "  Router: $ROUTER_IP"

# Wait for router to be ready
sleep 2

# Remove default route
ip route del default 2>/dev/null || true

# Add default route via router
ip route add default via $ROUTER_IP

# Add specific routes for other IPFS networks via router
for i in 1 2 3 4 5 6 7 8 9 10; do
  if [ "172.31.$i.0/24" != "${NETWORK_PREFIX}.0/24" ]; then
    ip route add 172.31.$i.0/24 via $ROUTER_IP 2>/dev/null || true
  fi
done

# Add route for bench network
ip route add 172.31.100.0/24 via $ROUTER_IP 2>/dev/null || true

echo "Routing table:"
ip route

echo "✓ Routing setup complete"
