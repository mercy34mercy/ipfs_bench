# Router Pod Architecture - 使い方

## 概要

`docker-compose-router.yml` は、各IPFSノードに**現実的な帯域制限**を適用した構成です。

従来の `pumba` アプローチと異なり、tc (Traffic Control) と ifb (Intermediate Functional Block) を使用して、**Egress（送信）とIngress（受信）の両方**を制限します。

## 主な違い

| 項目 | 従来 (pumba) | Router Pod (tc/ifb) |
|------|-------------|---------------------|
| Egress制限 | ✅ 可能 | ✅ 可能 |
| Ingress制限 | ❌ 不可 | ✅ **可能** |
| 現実性 | ⚠️ 低い | ✅ **高い** |
| 設定方法 | 外部コンテナ | ノード内蔵 |

## クイックスタート

### 1. 起動

```bash
# Router Pod版を起動
docker-compose -f docker-compose-router.yml up -d

# ログを確認（各ノードのTC設定が表示される）
docker-compose -f docker-compose-router.yml logs ipfs-org1
```

### 2. テスト実行

既存のテストコマンドがそのまま使えます：

```bash
# ベンチマークテストを実行
docker exec ipfs-bench python benchmark.py

# または、Makefileを使用
make test-router  # 後述のMakefile追加が必要
```

### 3. 帯域制限の確認

各ノードのTC設定を確認できます：

```bash
# ipfs-org1のTC設定を確認
docker exec ipfs-org1 tc qdisc show

# ifb0（ingress用）の設定を確認
docker exec ipfs-org1 tc qdisc show dev ifb0
```

### 4. 停止とクリーンアップ

```bash
# 停止
docker-compose -f docker-compose-router.yml down

# データも削除
docker-compose -f docker-compose-router.yml down -v
```

## 設定のカスタマイズ

### 環境変数ファイルを使用

`.env.router` ファイルで設定を管理できます：

```bash
# .env.router を編集
vim .env.router

# 設定を適用して起動
docker-compose -f docker-compose-router.yml --env-file .env.router up -d
```

### よくある設定例

#### 例1: 全ノード10Mbps、50ms遅延

```bash
# .env.router
BANDWIDTH_RATE=10mbit
NETWORK_DELAY=50ms
PACKET_LOSS=0
```

#### 例2: 異なる帯域を各ノードに設定

```bash
# .env.router
# Org1: 高速回線（100Mbps）
ORG1_BANDWIDTH_RATE=100mbit
ORG1_NETWORK_DELAY=20ms

# Org2: 標準回線（10Mbps）
ORG2_BANDWIDTH_RATE=10mbit
ORG2_NETWORK_DELAY=50ms

# Org3: 低速回線（2Mbps）
ORG3_BANDWIDTH_RATE=2mbit
ORG3_NETWORK_DELAY=100ms
```

#### 例3: パケットロスを含む不安定な回線

```bash
# .env.router
BANDWIDTH_RATE=5mbit
NETWORK_DELAY=100ms
PACKET_LOSS=2  # 2% packet loss
```

### コマンドラインから設定

環境変数を直接指定して起動することもできます：

```bash
# 全ノード2Mbpsで起動
BANDWIDTH_RATE=2mbit docker-compose -f docker-compose-router.yml up -d

# ベンチマーククライアントのみ変更
BENCH_BANDWIDTH_RATE=1mbit docker-compose -f docker-compose-router.yml up -d ipfs-bench
```

## 動的な帯域変更

起動後に帯域を変更することもできます：

```bash
# ipfs-org1の帯域を1Mbpsに変更
docker exec ipfs-org1 sh -c "
  tc qdisc change dev eth0 root tbf rate 1mbit burst 16kbit latency 400ms
  tc qdisc change dev ifb0 root tbf rate 1mbit burst 16kbit latency 400ms
"

# 確認
docker exec ipfs-org1 tc qdisc show
```

## トラブルシューティング

### TC設定が見えない

```bash
# コンテナ内でTC設定を確認
docker exec ipfs-org1 tc qdisc show

# 出力例（正常）:
# qdisc tbf 1: dev eth0 root refcnt 2 rate 10Mbit burst 4Kb lat 400.0ms
# qdisc ingress ffff: dev eth0 parent ffff:fff1
# qdisc tbf 1: dev ifb0 root refcnt 2 rate 10Mbit burst 4Kb lat 400.0ms
```

### ifbモジュールが読み込めない

```bash
# ホストでifbモジュールを読み込む
sudo modprobe ifb numifbs=10

# 確認
lsmod | grep ifb
```

### 帯域制限が効いていない

```bash
# コンテナのログを確認（TC設定の詳細が出力される）
docker logs ipfs-org1

# 出力例に以下が含まれるはずです：
# ✓ Egress rate limit: 10mbit
# ✓ Ingress rate limit: 10mbit
```

## ベンチマークテスト

### 帯域制限の効果を測定

```bash
# ipfs-benchから各ノードへの速度テスト
docker exec ipfs-bench sh -c "
  # iperf3がインストールされている場合
  iperf3 -c ipfs-org1 -t 10
"

# または、IPFSファイル転送で測定
docker exec ipfs-bench python benchmark.py --scenario bandwidth-test
```

### 従来方式との比較

```bash
# 1. Router Pod版でテスト
docker-compose -f docker-compose-router.yml up -d
docker exec ipfs-bench python benchmark.py --output results-router.json

# 2. 従来版（pumba）でテスト
docker-compose down
docker-compose up -d
./scripts/network-chaos/limit-bandwidth-all.sh 10mbit
docker exec ipfs-bench python benchmark.py --output results-pumba.json

# 3. 結果を比較
diff results-router.json results-pumba.json
```

## Makefileへの統合

既存のMakefileに以下を追加することで、簡単に使えます：

```makefile
# Router Pod版の起動
.PHONY: up-router
up-router:
	docker-compose -f docker-compose-router.yml up -d

# Router Pod版の停止
.PHONY: down-router
down-router:
	docker-compose -f docker-compose-router.yml down

# Router Pod版でテスト
.PHONY: test-router
test-router: up-router
	@echo "Waiting for nodes to be ready..."
	@sleep 10
	docker exec ipfs-bench python benchmark.py
	@echo "Test completed!"

# Router Pod版のログ確認
.PHONY: logs-router
logs-router:
	docker-compose -f docker-compose-router.yml logs -f

# Router Pod版のTC設定確認
.PHONY: check-tc
check-tc:
	@echo "=== ipfs-org1 TC Configuration ==="
	@docker exec ipfs-org1 tc qdisc show
	@echo ""
	@echo "=== ipfs-org1 IFB Configuration ==="
	@docker exec ipfs-org1 tc qdisc show dev ifb0
```

## プリセット設定例

### 高速ネットワーク（100Mbps）

```bash
BANDWIDTH_RATE=100mbit NETWORK_DELAY=20ms \
  docker-compose -f docker-compose-router.yml up -d
```

### 標準ネットワーク（10Mbps）

```bash
BANDWIDTH_RATE=10mbit NETWORK_DELAY=50ms \
  docker-compose -f docker-compose-router.yml up -d
```

### 低速ネットワーク（2Mbps、ADSL相当）

```bash
BANDWIDTH_RATE=2mbit NETWORK_DELAY=100ms \
  docker-compose -f docker-compose-router.yml up -d
```

### モバイル/4G（5Mbps、パケットロスあり）

```bash
BANDWIDTH_RATE=5mbit NETWORK_DELAY=100ms PACKET_LOSS=1 \
  docker-compose -f docker-compose-router.yml up -d
```

### 衛星回線（1Mbps、高遅延、パケットロスあり）

```bash
BANDWIDTH_RATE=1mbit NETWORK_DELAY=500ms PACKET_LOSS=2 \
  docker-compose -f docker-compose-router.yml up -d
```

## 関連ドキュメント

- [Router Pod Architecture 詳細](./router-pod-architecture.md) - アーキテクチャの説明
- [帯域制限の問題点と解決策](./bandwidth-limitation-analysis.md) - 従来アプローチとの比較
- [ネットワーク図](../network-bandwidth-diagram.drawio) - 視覚的な説明

## 注意事項

1. **NET_ADMIN Capability必須**: TC設定にはNET_ADMIN capabilityが必要です
2. **ifbモジュール**: ホストでifbカーネルモジュールが有効である必要があります
3. **既存pumbaとの併用不可**: Router Pod版とpumbaは併用できません（設定が競合します）
4. **パフォーマンス**: TC設定は軽量ですが、極端に低い帯域（<100kbps）では不安定になることがあります

## FAQ

### Q: 既存のテストスクリプトは使えますか？

A: はい、そのまま使えます。`docker-compose-router.yml`を使用しても、コンテナ名やネットワーク構成は同じです。

### Q: pumbaは必要ですか？

A: いいえ、Router Pod版ではpumbaは不要です。TC設定が各ノードに組み込まれています。

### Q: 起動が遅くなりますか？

A: TC設定の初期化に数秒かかりますが、大きな遅延はありません。

### Q: ノード数を増やせますか？

A: はい、`docker-compose-router.yml`に新しいノードを追加し、同様の設定を行えば増やせます。

### Q: Windows/Macでも動きますか？

A: はい、Docker DesktopのLinux VMで動作します。ifbモジュールはVM内で自動的に処理されます。
