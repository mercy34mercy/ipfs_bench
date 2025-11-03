#!/bin/sh
#
# ipfs-bench routing setup
# Route all IPFS traffic through the router
#

set -e

echo "Setting up routing for ipfs-bench..."

# Router IP address
ROUTER_IP="172.31.100.2"

# Wait for router to be ready
sleep 2

# Remove default route
ip route del default 2>/dev/null || true

# Add default route via router
ip route add default via $ROUTER_IP

# Add specific routes for each IPFS network via router
for i in 1 2 3 4 5 6 7 8 9 10; do
  ip route add 172.31.$i.0/24 via $ROUTER_IP 2>/dev/null || true
done

echo "Routing table configured:"
ip route

echo "✓ Routing setup complete"
