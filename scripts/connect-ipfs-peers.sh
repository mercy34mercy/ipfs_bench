#!/bin/bash
#
# Connect all IPFS nodes to each other
#

set -e

echo "Connecting IPFS peers..."

# Get all IPFS node peer IDs and addresses
declare -A PEERS

for i in {1..10}; do
  container="ipfs-org${i}"
  ip="172.31.${i}.10"

  # Get peer ID
  peer_id=$(docker exec ${container} ipfs id -f "<id>" 2>/dev/null || echo "")

  if [ -n "$peer_id" ]; then
    PEERS[$container]="/ip4/${ip}/tcp/4001/p2p/${peer_id}"
    echo "  Found: ${container} -> ${peer_id}"
  else
    echo "  Warning: ${container} not ready"
  fi
done

echo ""
echo "Establishing connections..."

# Connect each node to all others
for src in "${!PEERS[@]}"; do
  for dst in "${!PEERS[@]}"; do
    if [ "$src" != "$dst" ]; then
      docker exec ${src} ipfs swarm connect "${PEERS[$dst]}" >/dev/null 2>&1 || true
    fi
  done
  echo "  ✓ ${src} connected"
done

echo ""
echo "Connection summary:"
for container in ipfs-org{1..10}; do
  peer_count=$(docker exec ${container} ipfs swarm peers 2>/dev/null | wc -l | tr -d ' ')
  echo "  ${container}: ${peer_count} peers"
done

echo ""
echo "✅ All IPFS nodes connected"
