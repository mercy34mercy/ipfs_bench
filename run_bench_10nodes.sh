#!/bin/bash

# 10ノードIPFSベンチマーク実行スクリプト
# アップロード・ダウンロード両方を測定

echo "====================================="
echo "IPFS 10-Node Upload/Download Benchmark"
echo "====================================="

# カラー定義
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 1. IPFSコンテナの起動確認と起動
echo -e "\n${GREEN}[1/3] Checking IPFS containers...${NC}"
RUNNING_CONTAINERS=$(docker ps --format "table {{.Names}}" | grep -c "ipfs-org" || true)

if [ "$RUNNING_CONTAINERS" -lt 10 ]; then
    echo "Starting 10-node IPFS network..."
    docker-compose up -d

    # 起動を待つ
    echo "Waiting for nodes to be ready..."
    sleep 10

    # 各ノードのヘルスチェック
    for i in {1..10}; do
        PORT=$((5000 + i))
        echo -n "Checking node $i (port $PORT)... "

        MAX_ATTEMPTS=30
        ATTEMPTS=0
        while [ $ATTEMPTS -lt $MAX_ATTEMPTS ]; do
            if curl -s "http://127.0.0.1:$PORT/api/v0/id" > /dev/null 2>&1; then
                echo -e "${GREEN}OK${NC}"
                break
            fi
            ATTEMPTS=$((ATTEMPTS + 1))
            sleep 1
        done

        if [ $ATTEMPTS -eq $MAX_ATTEMPTS ]; then
            echo -e "${RED}FAILED${NC}"
            echo "Node $i is not responding. Please check the logs."
            exit 1
        fi
    done
else
    echo -e "${GREEN}All 10 nodes are already running${NC}"
fi

# 2. テストファイルの確認
echo -e "\n${GREEN}[2/3] Checking test files...${NC}"
TEST_FILES_DIR="../test-files"

if [ ! -d "$TEST_FILES_DIR" ]; then
    echo -e "${RED}Test files directory not found: $TEST_FILES_DIR${NC}"
    echo "Please create test files first."
    exit 1
fi

echo "Test files found:"
ls -lh "$TEST_FILES_DIR" | grep -E "\.dat$"

# 3. ベンチマークの実行
echo -e "\n${GREEN}[3/3] Running benchmark...${NC}"

# ベンチマークパラメータ
RUNS=${1:-10}  # デフォルト10ラン、引数で変更可能
OUTPUT_CSV="bench_upload_download_$(date +%Y%m%d_%H%M%S).csv"

echo "Configuration:"
echo "  - Number of runs: $RUNS"
echo "  - Output CSV: $OUTPUT_CSV"
echo "  - Test files: $(ls $TEST_FILES_DIR/*.dat 2>/dev/null | wc -l) files"
echo ""

# ベンチマーク実行
go run bench_updown/main.go \
    -api-template "http://127.0.0.1:500%d" \
    -dir "$TEST_FILES_DIR" \
    -runs $RUNS \
    -csv "$OUTPUT_CSV" \
    -nodes 10 \
    -timeout 5m

echo -e "\n${GREEN}Benchmark completed!${NC}"
echo "Results saved to: $OUTPUT_CSV"

# 結果の簡単な分析
if [ -f "$OUTPUT_CSV" ]; then
    echo -e "\nQuick statistics:"
    echo "Total operations: $(tail -n +2 $OUTPUT_CSV | wc -l)"

    # 平均スループットを計算（要: awk）
    if command -v awk &> /dev/null; then
        AVG_UPLOAD=$(tail -n +2 $OUTPUT_CSV | awk -F',' '{sum+=$9; count++} END {if(count>0) printf "%.2f", sum/count}')
        AVG_DOWNLOAD=$(tail -n +2 $OUTPUT_CSV | awk -F',' '{sum+=$10; count++} END {if(count>0) printf "%.2f", sum/count}')
        echo "Average upload throughput: $AVG_UPLOAD MiB/s"
        echo "Average download throughput: $AVG_DOWNLOAD MiB/s"
    fi
fi

echo -e "\n${GREEN}Done!${NC}"