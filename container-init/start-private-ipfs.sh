#!/bin/sh
set -e

CONFIG_PATH=${IPFS_PATH:-/data/ipfs}/config

if [ ! -f "$CONFIG_PATH" ]; then
  ipfs init
  ipfs bootstrap rm --all
fi

# Private network hardening for recent Kubo versions
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

exec ipfs daemon --migrate=true --enable-gc
