#!/bin/sh
#
# Wrapper script for IPFS with routing setup
#

set -e

echo "=========================================="
echo "IPFS Node with Router-based Networking"
echo "=========================================="

# Install iproute2 for routing commands
echo "Installing iproute2..."
apt-get update -qq && apt-get install -y -qq iproute2 > /dev/null 2>&1

# Setup routing
/container-init/setup-ipfs-routing.sh

echo ""
echo "Starting IPFS daemon..."
echo "=========================================="

# Start IPFS with the original script
exec /container-init/start-private-ipfs.sh
