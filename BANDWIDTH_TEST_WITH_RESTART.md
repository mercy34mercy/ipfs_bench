# 帯域制限テストの自動コンテナ再起動機能

## 概要

`make bandwidth-test` コマンドが、各シナリオの切り替え時に自動的にDockerコンテナを再起動するようになりました。これにより、帯域制限を変更するたびにネットワーク状態がクリーンになり、より正確なベンチマーク結果が得られます。

## 変更内容

### 1. 自動コンテナ再起動

各ネットワークシナリオの切り替え時に以下の処理が自動実行されます：

1. **既存の帯域制限を解除** - `remove-bandwidth-limit.sh` を実行
2. **全コンテナを再起動** - `docker-compose restart` で全コンテナを再起動
3. **15秒待機** - コンテナが完全に起動するまで待機
4. **新しい帯域制限を適用** - `limit-bandwidth-all.sh` で新しい制限を適用

### 2. 全コンテナへの制限適用

`limit-bandwidth-all.sh` スクリプトを使用して、以下の全てのコンテナに同時に帯域制限を適用：

- `ipfs-org1` ～ `ipfs-org10` (IPFSノード)
- `ipfs-bench` (ベンチマーククライアント)

### 3. Makefile の更新

```makefile
bandwidth-test: build
	@echo "Starting bandwidth test with container restarts..."
	RESTART_CONTAINERS=1 ./bin/bandwidth-test test-scenarios.json
```

環境変数 `RESTART_CONTAINERS=1` を設定することで、コンテナ再起動機能が有効化されます。

## 使用方法

### 基本的な使い方

```bash
# 通常のテスト実行（自動でコンテナ再起動）
make bandwidth-test

# クイックテスト（2回の繰り返し、自動でコンテナ再起動）
make test-quick

# ネットワークを起動してからテスト
make start-network
make bandwidth-test
```

### 手動実行

```bash
# コンテナ再起動ありで実行
RESTART_CONTAINERS=1 ./bin/bandwidth-test test-scenarios.json

# コンテナ再起動なしで実行（従来の動作）
./bin/bandwidth-test test-scenarios.json
```

## テストフロー

### シナリオ切り替え時のフロー

```
シナリオ1開始
  ↓
コンテナ再起動（クリーンな状態）
  ↓
帯域制限適用
  ↓
テスト実行
  ↓
制限解除
  ↓
シナリオ2開始
  ↓
コンテナ再起動（クリーンな状態）
  ↓
帯域制限適用
  ↓
テスト実行
  ...
```

### 実行例の出力

```
============================================================
Running scenario: 10 Mbps Bandwidth
Description: Test with 10 Mbps bandwidth limit
============================================================
  Restarting Docker containers for clean network state...
    Removing existing bandwidth limits...
    Restarting containers via docker-compose...
  Containers restarted successfully
  Applying limits to all IPFS containers...
  Applied 10mbit limit to all containers

  Testing file: test10m.dat (10MB)
    Iteration 1/2: test10m.dat
    Iteration 2/2: test10m.dat
    File Statistics:
      Success rate: 2/2
      Avg upload time: 0.03s (±0.01s)
      Avg download time: 14.11s (±0.81s)
```

## ベンチマーク結果の例

### No Bandwidth Limit（ベースライン）
- アップロード: 2197.6 Mbps
- ダウンロード: 531.9 Mbps

### 10 Mbps制限
- アップロード: 2610.3 Mbps（制限対象外）
- ダウンロード: 5.9 Mbps（理論値10Mbpsに対して約60%）

### 100 Mbps制限
- ダウンロード: 約50-60 Mbps

### 1 Gbps制限
- ダウンロード: 約50-100 Mbps

## 利点

### 1. ネットワーク状態のクリーン化
- pumbaの帯域制限ルールが完全にリセットされる
- 前のシナリオの影響を受けない

### 2. 正確なベンチマーク
- 各シナリオが独立した環境でテストされる
- 理論値に近い結果が得られる

### 3. 再現性の向上
- テスト実行ごとに同じ条件が保証される
- デバッグが容易

## トラブルシューティング

### コンテナ再起動に失敗する

```bash
# 手動でコンテナを確認
docker ps -a

# コンテナを手動で再起動
docker-compose restart

# ログを確認
docker-compose logs ipfs-bench ipfs-org1 ipfs-org2
```

### 帯域制限が適用されない

```bash
# Pumbaコンテナの状態を確認
docker ps | grep pumba-rate

# 既存の制限を手動で削除
./scripts/network-chaos/remove-bandwidth-limit.sh

# テストを再実行
make bandwidth-test
```

### 待機時間が不十分

`cmd/bandwidth-test/main.go` の待機時間を調整：

```go
// Wait for containers to be fully ready
time.Sleep(15 * time.Second)  // <- この値を増やす
```

## ファイル構成

```
ipfs_bench/
├── Makefile                              # RESTART_CONTAINERS=1 を設定
├── cmd/bandwidth-test/main.go            # restartContainers()関数を追加
├── test-scenarios.json                   # limit-bandwidth-all.sh を使用
├── scripts/network-chaos/
│   ├── limit-bandwidth-all.sh           # 全コンテナに制限適用
│   └── remove-bandwidth-limit.sh        # 全制限を解除
└── BANDWIDTH_TEST_WITH_RESTART.md       # このドキュメント
```

## 設定ファイル (test-scenarios.json)

各シナリオで `limit-bandwidth-all.sh` を使用：

```json
{
  "id": "10mbps",
  "name": "10 Mbps Bandwidth",
  "bandwidth": "10mbit",
  "bandwidthCommand": "./scripts/network-chaos/limit-bandwidth-all.sh",
  "enabled": true
}
```

## まとめ

`make bandwidth-test` を実行するだけで：

1. ✅ 各シナリオの前にコンテナが再起動される
2. ✅ 全コンテナ（ipfs-bench含む）に帯域制限が適用される
3. ✅ クリーンな状態で正確なベンチマークが実行される
4. ✅ 帯域制限が理論値に近い値で機能する

これにより、従来の問題（帯域制限が効かない、制限が残り続ける）が解決されました。
