#!/bin/bash

# Script to run IPFS benchmark from inside Docker network
# This ensures the benchmark client is subject to pumba bandwidth restrictions
# Usage: ./run-benchmark-docker.sh [options]

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

# Default parameters
API_URL="http://ipfs-org1:5001"
RUNS=10
INCLUDE="test10m.dat,test50m.dat"
TIMEOUT="5m"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --api)
            API_URL="$2"
            shift 2
            ;;
        --runs)
            RUNS="$2"
            shift 2
            ;;
        --include)
            INCLUDE="$2"
            shift 2
            ;;
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [options]"
            echo "Options:"
            echo "  --api <url>       IPFS API URL (default: http://ipfs-org1:5001)"
            echo "  --runs <n>        Number of runs (default: 10)"
            echo "  --include <glob>  File pattern to include (default: test10m.dat,test50m.dat)"
            echo "  --timeout <dur>   Timeout per upload (default: 5m)"
            echo ""
            echo "Example:"
            echo "  $0 --api http://ipfs-org1:5001 --runs 5 --include 'test10m.dat' --timeout 2m"
            exit 0
            ;;
        *)
            print_red "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Start all IPFS nodes and benchmark container
print_blue "Starting all IPFS nodes..."
docker-compose up -d ipfs-org1 ipfs-org2 ipfs-org3 ipfs-org4 ipfs-org5 \
                   ipfs-org6 ipfs-org7 ipfs-org8 ipfs-org9 ipfs-org10 \
                   ipfs-bench

print_blue "Waiting for containers to be healthy..."
sleep 15

# Check container status
print_blue "Checking container status..."
RUNNING=$(docker ps --filter "name=ipfs-org" --filter "status=running" --format "{{.Names}}" | wc -l)
print_yellow "Running IPFS nodes: $RUNNING/10"

if [ "$RUNNING" -lt 10 ]; then
    print_yellow "Warning: Not all IPFS nodes are running. Continuing anyway..."
fi

# Check if ipfs-bench container exists
if ! docker ps | grep -q ipfs-bench; then
    print_red "Error: ipfs-bench container not running"
    exit 1
fi

print_blue "======================================"
print_blue "IPFS Benchmark (Docker Mode)"
print_blue "======================================"
print_yellow "API URL: $API_URL"
print_yellow "Runs: $RUNS"
print_yellow "Include: $INCLUDE"
print_yellow "Timeout: $TIMEOUT"
print_yellow "IPFS Nodes Running: $RUNNING/10"
print_blue "======================================\n"

# Run benchmark inside Docker container
print_blue "Executing benchmark..."
docker exec ipfs-bench /app/ipfs-bench \
    --api "$API_URL" \
    --dir /test-files \
    --runs "$RUNS" \
    --include "$INCLUDE" \
    --timeout "$TIMEOUT" \
    --csv "/results/bench_results_$(date +%Y%m%d_%H%M%S).csv"

if [ $? -eq 0 ]; then
    print_green "\n✅ Benchmark completed successfully"
    print_blue "Results saved in ./test-results/"

    # Play notification sound on macOS
    if [[ "$OSTYPE" == "darwin"* ]]; then
        osascript -e 'display notification "Benchmark completed successfully" with title "IPFS Benchmark" sound name "Glass"'
    fi
else
    print_red "\n❌ Benchmark failed"

    # Play error sound on macOS
    if [[ "$OSTYPE" == "darwin"* ]]; then
        osascript -e 'display notification "Benchmark failed" with title "IPFS Benchmark" sound name "Basso"'
    fi
    exit 1
fi
