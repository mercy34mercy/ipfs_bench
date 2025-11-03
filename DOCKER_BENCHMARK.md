# Docker内でIPFSベンチマークを実行する方法

## 概要

pumbaの帯域制限を正しく適用するため、ベンチマークツール(`main.go`)をDockerコンテナ内で実行する構成に変更しました。これにより、ベンチマーククライアントとIPFSノード間の通信にも帯域制限が適用されます。

## アーキテクチャ

```
┌─────────────────┐
│  ipfs-bench     │  ← ベンチマーククライアント（Dockerコンテナ）
│  (Docker)       │
└────────┬────────┘
         │
    private_ipfs network (帯域制限が適用される)
         │
┌────────┴────────────────────────┐
│  ipfs-org1, ipfs-org2, ...      │  ← IPFSノード
│  (Docker)                       │
└─────────────────────────────────┘
         │
    Pumba (帯域制限ツール)
```

## セットアップ

### 1. Dockerイメージのビルド

```bash
# ベンチマークコンテナをビルド
docker-compose build ipfs-bench

# または全体を起動
docker-compose up -d
```

### 2. コンテナの確認

```bash
docker ps | grep -E "(ipfs-org|ipfs-bench)"
```

## 使用方法

### 基本的なベンチマーク実行

```bash
# デフォルト設定で実行（test10m.dat, test50m.dat を10回）
./scripts/run-benchmark-docker.sh

# カスタム設定で実行
./scripts/run-benchmark-docker.sh \
  --api http://ipfs-org1:5001 \
  --runs 5 \
  --include "test10m.dat,test50m.dat,test100m.dat" \
  --timeout 5m
```

### 帯域制限の適用

#### 全コンテナに帯域制限を適用

```bash
# 10Mbpsに制限
./scripts/network-chaos/limit-bandwidth-all.sh 10mbit

# 100Mbpsに制限
./scripts/network-chaos/limit-bandwidth-all.sh 100mbit

# 1Gbpsに制限
./scripts/network-chaos/limit-bandwidth-all.sh 1gbit
```

このスクリプトは以下のコンテナに帯域制限を適用します：
- `ipfs-bench` (ベンチマーククライアント)
- `ipfs-org1` 〜 `ipfs-org10` (IPFSノード)

#### 帯域制限の解除

```bash
# 全ての帯域制限を解除
./scripts/network-chaos/remove-bandwidth-limit.sh
```

#### 制限状態の確認

```bash
# Pumbaコンテナの確認
docker ps | grep pumba-rate
```

### 完全なテストフロー例

```bash
# 1. 環境を起動
docker-compose up -d

# 2. 帯域制限を適用（10Mbps）
./scripts/network-chaos/limit-bandwidth-all.sh 10mbit

# 3. ベンチマーク実行
./scripts/run-benchmark-docker.sh \
  --api http://ipfs-org1:5001 \
  --runs 10 \
  --include "test10m.dat,test50m.dat" \
  --timeout 5m

# 4. 帯域制限を解除
./scripts/network-chaos/remove-bandwidth-limit.sh

# 5. 制限なしでベンチマーク実行（ベースライン）
./scripts/run-benchmark-docker.sh \
  --api http://ipfs-org1:5001 \
  --runs 10 \
  --include "test10m.dat,test50m.dat" \
  --timeout 5m
```

## トラブルシューティング

### ipfs-benchコンテナが起動しない

```bash
# ログを確認
docker logs ipfs-bench

# 手動で起動
docker-compose up -d ipfs-bench
```

### 帯域制限が効かない

```bash
# Pumbaコンテナの状態を確認
docker ps -a | grep pumba-rate

# 既存の制限を削除してやり直し
./scripts/network-chaos/remove-bandwidth-limit.sh
./scripts/network-chaos/limit-bandwidth-all.sh 10mbit
```

### コンテナ内で直接コマンド実行

```bash
# ipfs-benchコンテナに入る
docker exec -it ipfs-bench /bin/sh

# コンテナ内でベンチマーク実行
/app/ipfs-bench \
  --api http://ipfs-org1:5001 \
  --dir /test-files \
  --runs 5 \
  --include "test10m.dat"
```

## ファイル構成

```
ipfs_bench/
├── Dockerfile.bench              # ベンチマークツールのDockerfile
├── docker-compose.yml            # ipfs-benchコンテナを含む設定
├── main.go                       # ベンチマークツール本体
├── scripts/
│   ├── run-benchmark-docker.sh   # Docker内でベンチマーク実行
│   └── network-chaos/
│       ├── limit-bandwidth-all.sh       # 全コンテナに帯域制限適用
│       └── remove-bandwidth-limit.sh    # 帯域制限解除
├── test-files/                   # テストファイル
└── test-results/                 # 結果出力先
```

## 従来の方法との違い

### 従来（ホストから実行）

```bash
# ホストマシンから直接実行
go run main.go --api http://localhost:5001
```

**問題点：**
- ホスト → Docker間の通信は帯域制限の対象外
- pumbaはDockerネットワーク内のコンテナ間通信のみ制限可能

### 新方式（Docker内から実行）

```bash
# Dockerコンテナ内から実行
docker exec ipfs-bench /app/ipfs-bench --api http://ipfs-org1:5001
```

**利点：**
- ベンチマーククライアントもDocker内で動作
- コンテナ間通信にpumbaの帯域制限が適用される
- より現実的なネットワーク条件をシミュレート可能

## 結果の確認

```bash
# CSV結果を確認
ls -lh test-results/

# 最新の結果を表示
cat test-results/bench_results_*.csv | tail -20
```
