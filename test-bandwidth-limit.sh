#!/bin/bash

# Quick test to verify bandwidth limitation

echo "=== Testing Bandwidth Limitation ==="
echo

# Test file (10MB)
TEST_FILE="/tmp/test-10mb.dat"
dd if=/dev/urandom of=$TEST_FILE bs=1M count=10 2>/dev/null

echo "1. Testing without bandwidth limit..."
START=$(date +%s%N)
# Upload to ipfs-org1
CID=$(curl -s -X POST -F file=@$TEST_FILE http://localhost:5001/api/v0/add | jq -r .Hash)
# Download from ipfs-org2
curl -s -X POST "http://localhost:5002/api/v0/cat?arg=$CID" > /dev/null
END=$(date +%s%N)
NO_LIMIT_TIME=$((($END - $START) / 1000000))
echo "   Time: ${NO_LIMIT_TIME}ms"

# Apply 10mbit limit
echo
echo "2. Applying 10mbit limit to all containers..."
for i in {1..10}; do
    ./scripts/network-chaos/limit-bandwidth.sh ipfs-org$i 10mbit >/dev/null 2>&1
done
sleep 3

echo "3. Testing with 10mbit bandwidth limit..."
START=$(date +%s%N)
# Upload to ipfs-org1
CID=$(curl -s -X POST -F file=@$TEST_FILE http://localhost:5001/api/v0/add | jq -r .Hash)
# Download from ipfs-org2
curl -s -X POST "http://localhost:5002/api/v0/cat?arg=$CID" > /dev/null
END=$(date +%s%N)
LIMITED_TIME=$((($END - $START) / 1000000))
echo "   Time: ${LIMITED_TIME}ms"

# Remove limits
echo
echo "4. Removing bandwidth limits..."
for i in {1..10}; do
    ./scripts/network-chaos/stop-chaos.sh ipfs-org$i >/dev/null 2>&1
done

# Calculate difference
DIFF=$((LIMITED_TIME - NO_LIMIT_TIME))
RATIO=$((LIMITED_TIME * 100 / NO_LIMIT_TIME))

echo
echo "=== Results ==="
echo "Without limit: ${NO_LIMIT_TIME}ms"
echo "With 10mbit limit: ${LIMITED_TIME}ms"
echo "Difference: ${DIFF}ms (${RATIO}% of original)"

if [ $RATIO -gt 150 ]; then
    echo "✅ Bandwidth limitation appears to be working (>50% slower)"
else
    echo "❌ Bandwidth limitation may not be working effectively"
fi

rm -f $TEST_FILE