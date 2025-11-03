.PHONY: all build test bandwidth-test clean up-router down-router test-router check-tc logs-router

# Build all binaries
all: build

# Build the bandwidth test binary
build:
	go build -o bin/bandwidth-test cmd/bandwidth-test/*.go

# Run bandwidth test with default config
# This target ensures containers are restarted between bandwidth limit changes
# Now runs inside Docker to ensure bandwidth limits apply to upload as well
bandwidth-test: build
	@echo "Rebuilding ipfs-bench container..."
	@docker-compose build ipfs-bench
	@echo "Starting bandwidth test inside Docker with container restarts..."
	@docker exec -e RESTART_CONTAINERS=1 ipfs-bench /app/bandwidth-test /app/test-scenarios.json

# Run a quick test (reduced iterations for testing)
test-quick: build
	@echo "Rebuilding ipfs-bench container..."
	@docker-compose build ipfs-bench
	@echo "Using demo test config (2 iterations)..."
	@docker exec -e RESTART_CONTAINERS=1 ipfs-bench /app/bandwidth-test /app/test-scenarios-demo.json

# Start IPFS network
start-network:
	docker-compose up -d
	@echo "Waiting for containers to start..."
	@sleep 5
	@docker ps | grep ipfs-org

# Stop IPFS network
stop-network:
	docker-compose down


# Clean build artifacts
clean:
	rm -rf bin/
	rm -rf test-results/

# Install dependencies
deps:
	go mod tidy

# Check if containers are running
check:
	@docker ps --format "table {{.Names}}\t{{.Status}}" | grep ipfs-org || echo "No IPFS containers running"

# Network speed test from ipfs-bench to ipfs-org1
network-speed-test:
	@echo "Setting up network speed test tools..."
	@docker exec ipfs-bench sh -c "apk add --no-cache curl iperf3 2>/dev/null || true" > /dev/null
	@echo ""
	@echo "============================================"
	@echo "Network Speed Test: ipfs-bench → ipfs-org1"
	@echo "============================================"
	@echo ""
	@echo "1. Ping Test (latency):"
	@docker exec ipfs-bench ping -c 5 ipfs-org1
	@echo ""
	@echo "2. Upload Speed Test (10MB):"
	@docker exec ipfs-bench sh -c "dd if=/dev/zero bs=10M count=1 2>/dev/null | curl -X POST -F file=@- -w '\nSpeed: %{speed_upload} bytes/sec (%.2f MB/s)\nTime: %{time_total}s\n' http://ipfs-org1:5001/api/v0/add?quieter=true 2>/dev/null | tail -n 3"
	@echo ""
	@echo "3. Upload Speed Test (100MB):"
	@docker exec ipfs-bench sh -c "dd if=/dev/zero bs=10M count=10 2>/dev/null | curl -X POST -F file=@- -w '\nSpeed: %{speed_upload} bytes/sec (%.2f MB/s)\nTime: %{time_total}s\n' http://ipfs-org1:5001/api/v0/add?quieter=true 2>/dev/null | tail -n 3"
	@echo ""
	@echo "============================================"

# Full test cycle: start network, run tests, stop network
full-test: start-network bandwidth-test stop-network

# ============================================
# Router Pod Architecture Targets
# ============================================

# Start Router Pod version (with realistic bandwidth limits)
up-router:
	@echo "Starting Router Pod architecture (tc/ifb bandwidth limits)..."
	docker-compose -f docker-compose-router.yml --env-file .env.router up -d
	@echo "Waiting for nodes to initialize TC settings..."
	@sleep 10
	@echo ""
	@echo "✅ Router Pod network started!"
	@echo "Run 'make check-tc' to verify TC configuration"

# Stop Router Pod version
down-router:
	@echo "Stopping Router Pod network..."
	docker-compose -f docker-compose-router.yml down

# Run bandwidth test with Router Pod architecture
test-router: build
	@echo "Ensuring Router Pod network is running..."
	@docker-compose -f docker-compose-router.yml up -d
	@sleep 5
	@echo "Rebuilding ipfs-bench container..."
	@docker-compose -f docker-compose-router.yml build ipfs-bench
	@echo "Starting bandwidth test with Router Pod architecture..."
	@docker exec -e RESTART_CONTAINERS=1 ipfs-bench /app/bandwidth-test /app/test-scenarios-router.json
	@echo ""
	@echo "✅ Router Pod test completed!"

# Quick test with Router Pod architecture
test-router-quick: build
	@echo "Ensuring Router Pod network is running..."
	@docker-compose -f docker-compose-router.yml up -d
	@sleep 5
	@echo "Rebuilding ipfs-bench container..."
	@docker-compose -f docker-compose-router.yml build ipfs-bench
	@echo "Starting quick test with Router Pod architecture..."
	@docker exec -e RESTART_CONTAINERS=1 ipfs-bench /app/bandwidth-test /app/test-scenarios-demo.json
	@echo ""
	@echo "✅ Router Pod quick test completed!"

# Change bandwidth on Router Pod routers
change-bandwidth-router:
	@if [ -z "$(RATE)" ]; then \
		echo "Error: RATE parameter required"; \
		echo "Usage: make change-bandwidth-router RATE=<rate>"; \
		echo "Example: make change-bandwidth-router RATE=50mbit"; \
		exit 1; \
	fi
	@./scripts/network-chaos/limit-bandwidth-routers.sh $(RATE)

# Check TC configuration on all nodes
check-tc:
	@echo "=========================================="
	@echo "Traffic Control Configuration"
	@echo "=========================================="
	@echo ""
	@echo "=== ipfs-bench ==="
	@docker exec ipfs-bench sh -c "echo 'Egress (eth0):' && tc qdisc show dev eth0 2>/dev/null || echo 'Not configured'" || echo "Container not running"
	@docker exec ipfs-bench sh -c "echo 'Ingress (ifb0):' && tc qdisc show dev ifb0 2>/dev/null || echo 'Not configured'" || echo "Container not running"
	@echo ""
	@echo "=== ipfs-org1 ==="
	@docker exec ipfs-org1 sh -c "echo 'Egress (eth0):' && tc qdisc show dev eth0" || echo "Container not running"
	@docker exec ipfs-org1 sh -c "echo 'Ingress (ifb0):' && tc qdisc show dev ifb0" || echo "Container not running"
	@echo ""
	@echo "=== ipfs-org2 ==="
	@docker exec ipfs-org2 sh -c "echo 'Egress (eth0):' && tc qdisc show dev eth0" || echo "Container not running"
	@docker exec ipfs-org2 sh -c "echo 'Ingress (ifb0):' && tc qdisc show dev ifb0" || echo "Container not running"
	@echo ""
	@echo "=== ipfs-org3 ==="
	@docker exec ipfs-org3 sh -c "echo 'Egress (eth0):' && tc qdisc show dev eth0" || echo "Container not running"
	@docker exec ipfs-org3 sh -c "echo 'Ingress (ifb0):' && tc qdisc show dev ifb0" || echo "Container not running"
	@echo "=========================================="

# Show logs for Router Pod network
logs-router:
	docker-compose -f docker-compose-router.yml logs -f

# Check Router Pod network status
check-router:
	@echo "Router Pod Network Status:"
	@docker-compose -f docker-compose-router.yml ps

# Compare Router Pod vs Pumba
compare-router-pumba: build
	@echo "=========================================="
	@echo "Comparing Router Pod vs Pumba"
	@echo "=========================================="
	@echo ""
	@echo "1. Testing with Router Pod architecture..."
	@make test-router-quick > /tmp/router-test.log 2>&1 || true
	@echo "   ✓ Router Pod test completed"
	@echo ""
	@echo "2. Stopping Router Pod network..."
	@make down-router
	@sleep 3
	@echo ""
	@echo "3. Testing with traditional Pumba approach..."
	@make start-network
	@./scripts/network-chaos/limit-bandwidth-all.sh 10mbit > /tmp/pumba-setup.log 2>&1 || true
	@make test-quick > /tmp/pumba-test.log 2>&1 || true
	@echo "   ✓ Pumba test completed"
	@echo ""
	@echo "Results saved to:"
	@echo "  - Router Pod: test-results/ (from Router Pod test)"
	@echo "  - Pumba: test-results/ (from Pumba test)"
	@echo ""
	@echo "Compare the bandwidth measurements to see the difference!"
	@echo "=========================================="

# Help
help:
	@echo "Available targets:"
	@echo ""
	@echo "Standard targets:"
	@echo "  make build              - Build the bandwidth test binary"
	@echo "  make bandwidth-test     - Run bandwidth tests (with container restarts)"
	@echo "  make test-quick         - Run quick test (2 iterations, with container restarts)"
	@echo "  make start-network      - Start IPFS Docker network"
	@echo "  make stop-network       - Stop IPFS Docker network"
	@echo "  make full-test          - Run complete test cycle"
	@echo "  make network-speed-test - Test network speed between ipfs-bench and ipfs-org1"
	@echo "  make clean              - Clean build artifacts"
	@echo "  make check              - Check container status"
	@echo ""
	@echo "Router Pod targets (realistic bandwidth simulation):"
	@echo "  make up-router          - Start Router Pod network with tc/ifb"
	@echo "  make down-router        - Stop Router Pod network"
	@echo "  make test-router        - Run full test with Router Pod"
	@echo "  make test-router-quick  - Run quick test with Router Pod"
	@echo "  make check-tc           - Check TC configuration on all nodes"
	@echo "  make logs-router        - Show Router Pod logs"
	@echo "  make check-router       - Check Router Pod network status"
	@echo "  make compare-router-pumba - Compare Router Pod vs Pumba approaches"
	@echo ""
	@echo "  make help               - Show this help"
	@echo ""
	@echo "Note: Router Pod uses tc/ifb for realistic bidirectional bandwidth limits"
	@echo "      (unlike pumba which only limits egress traffic)"