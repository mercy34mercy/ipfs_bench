# Router Pod Architecture - テスト実行ガイド

## テストシナリオ設定

Router Pod用のテストシナリオ設定が用意されています：

### test-scenarios-router.json

```json
{
  "testConfiguration": {
    "name": "IPFS Bandwidth Performance Test (Router Pod)",
    "iterations": 2
  },
  "networkScenarios": [
    { "id": "10mbps", "bandwidth": "10mbit" },
    { "id": "50mbps", "bandwidth": "50mbit" },
    { "id": "100mbps", "bandwidth": "100mbit" },
    { "id": "1gbps", "bandwidth": "1000mbit" }
  ]
}
```

各シナリオで以下のテストファイルをアップロード/ダウンロードします：
- test10m.dat (10MB)
- test50m.dat (50MB)
- test100m.dat (100MB)
- test250m.dat (250MB)
- test500m.dat (500MB)
- test1g.dat (1GB)

## クイックスタート

### 1. Router Podネットワークを起動

```bash
make up-router
```

### 2. テスト実行

```bash
# Router Pod用のフルテスト
make test-router

# または、クイックテスト（デモ用）
make test-router-quick
```

### 3. 結果確認

```bash
ls -lh test-results/
```

## 動的な帯域変更

テスト中に帯域を変更できます：

### コマンドで変更

```bash
# 50Mbpsに変更
make change-bandwidth-router RATE=50mbit

# 100Mbpsに変更
make change-bandwidth-router RATE=100mbit

# 2Mbpsに変更（低速回線シミュレーション）
make change-bandwidth-router RATE=2mbit
```

### スクリプトで直接変更

```bash
# 全ルータの帯域を変更
./scripts/network-chaos/limit-bandwidth-routers.sh 10mbit
```

### 設定確認

```bash
# TC設定を確認
docker exec router-org1 tc qdisc show

# ifb0（ingress）の設定を確認
docker exec router-org1 tc qdisc show dev ifb0
```

## テストシナリオのカスタマイズ

### 新しいシナリオを追加

`test-scenarios-router.json`を編集：

```json
{
  "networkScenarios": [
    {
      "id": "5mbps",
      "name": "5 Mbps Bandwidth",
      "description": "Slow home connection",
      "bandwidth": "5mbit",
      "bandwidthValue": 5000000,
      "bandwidthCommand": "/app/scripts/network-chaos/limit-bandwidth-routers.sh",
      "enabled": true
    }
  ]
}
```

### 遅延やパケットロスを追加

環境変数で設定：

```bash
# 遅延100ms、パケットロス2%
NETWORK_DELAY=100ms PACKET_LOSS=2 \
  ./scripts/network-chaos/limit-bandwidth-routers.sh 10mbit
```

## テストコマンド一覧

```bash
# Router Podネットワーク管理
make up-router              # 起動
make down-router           # 停止
make check-router          # ステータス確認
make logs-router           # ログ表示

# TC設定確認
make check-tc              # 全ノードのTC設定確認

# テスト実行
make test-router           # フルテスト（test-scenarios-router.json使用）
make test-router-quick     # クイックテスト

# 帯域変更
make change-bandwidth-router RATE=<rate>

# 比較テスト
make compare-router-pumba  # Router Pod vs Pumba比較
```

## 手動テスト

### 1. コンテナに入る

```bash
docker exec -it ipfs-bench sh
```

### 2. ファイルをアップロード

```bash
# ipfs-org1にアップロード
curl -X POST -F file=@/test-files/test10m.dat \
  http://ipfs-org1:5001/api/v0/add?quieter=true
```

### 3. CIDを確認してダウンロード

```bash
# CIDを使ってipfs-org2からダウンロード
curl "http://ipfs-org2:8080/ipfs/<CID>" -o /tmp/download.dat
```

### 4. 速度測定

```bash
# 時間を測定
time curl -X POST -F file=@/test-files/test100m.dat \
  http://ipfs-org1:5001/api/v0/add?quieter=true
```

## ネットワーク接続テスト

### Ping測定

```bash
# ipfs-org1からrouter-org1へ
docker exec ipfs-org1 ping -c 3 172.31.1.254

# ipfs-org1からrouter-org2へ（遅延確認）
docker exec ipfs-org1 ping -c 3 172.30.0.12
```

**期待される結果:**
- ローカルルータ: <1ms
- 他のルータ: 約100ms (egress 50ms + ingress 50ms)

### IPFSノード間通信確認

```bash
# ipfs-org1から他のノードを確認
docker exec ipfs-org1 ipfs swarm peers

# ピア接続
docker exec ipfs-org1 ipfs swarm connect /ip4/172.31.2.10/tcp/4001/p2p/<PEER_ID>
```

## トラブルシューティング

### 帯域が変更されない

```bash
# スクリプトを直接実行
./scripts/network-chaos/limit-bandwidth-routers.sh 50mbit

# ログ確認
docker logs router-org1 | tail -50
```

### TC設定がリセットされる

Router Podを再起動すると、環境変数の設定に戻ります：

```bash
# 再起動後は.env.routerの設定になる
make down-router
make up-router

# 帯域を再設定
make change-bandwidth-router RATE=50mbit
```

### テストが失敗する

```bash
# IPFSノードのログ確認
docker logs ipfs-org1

# ベンチマークコンテナのログ確認
docker logs ipfs-bench

# ネットワーク接続確認
docker exec ipfs-org1 ping -c 3 ipfs-org2
```

## ベストプラクティス

### 1. テスト前の準備

```bash
# ネットワークをクリーンアップ
make down-router

# 新しく起動
make up-router

# 初期状態を確認
make check-tc
```

### 2. テスト実行

```bash
# 帯域を設定
make change-bandwidth-router RATE=10mbit

# 数秒待つ（設定が反映されるまで）
sleep 5

# テスト実行
make test-router
```

### 3. 結果の保存

```bash
# タイムスタンプ付きで結果を保存
cp -r test-results test-results-$(date +%Y%m%d-%H%M%S)
```

## 異なる帯域でのテスト例

### シナリオ1: 低速回線（2Mbps）

```bash
make change-bandwidth-router RATE=2mbit
# テスト実行
docker exec ipfs-bench /app/bandwidth-test /app/test-scenarios-router.json
```

### シナリオ2: 標準回線（10Mbps）

```bash
make change-bandwidth-router RATE=10mbit
docker exec ipfs-bench /app/bandwidth-test /app/test-scenarios-router.json
```

### シナリオ3: 高速回線（100Mbps）

```bash
make change-bandwidth-router RATE=100mbit
docker exec ipfs-bench /app/bandwidth-test /app/test-scenarios-router.json
```

### シナリオ4: 超高速回線（1Gbps）

```bash
make change-bandwidth-router RATE=1000mbit
docker exec ipfs-bench /app/bandwidth-test /app/test-scenarios-router.json
```

## Pumba方式との違い

| 項目 | Pumba方式 | Router Pod方式 |
|------|----------|--------------|
| **設定ファイル** | test-scenarios.json | test-scenarios-router.json |
| **帯域変更スクリプト** | limit-bandwidth-all.sh | limit-bandwidth-routers.sh |
| **Ingress制限** | ❌ 不可 | ✅ 可能 |
| **複数ノードDL** | ❌ 30Mbps+ | ✅ 10Mbps |
| **起動コマンド** | docker-compose up | docker-compose -f docker-compose-router.yml up |
| **テストコマンド** | make test-quick | make test-router-quick |

## まとめ

Router Pod方式では：
- ✅ 現実的な帯域制限（Ingress/Egress両方）
- ✅ 動的な帯域変更が可能
- ✅ 各ノードが独立した「家庭回線」を持つ
- ✅ 正確なネットワークシミュレーション

### 推奨テストフロー

```bash
# 1. 起動
make up-router

# 2. 設定確認
make check-tc

# 3. テスト実行
make test-router

# 4. 結果確認
ls -lh test-results/

# 5. 停止
make down-router
```
