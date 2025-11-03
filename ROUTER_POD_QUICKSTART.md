# Router Pod Architecture - クイックスタート

## 🚀 今すぐ始める

### 1. 起動

```bash
make up-router
```

これで、各IPFSノードに**現実的な帯域制限**（10Mbps upload/download）が適用された環境が起動します。

### 2. TC設定を確認

```bash
make check-tc
```

各ノードのTraffic Control設定を確認できます。以下のような出力が表示されます：

```
=== ipfs-org1 ===
Egress (eth0):
qdisc tbf 1: root refcnt 2 rate 10Mbit burst 4Kb lat 400.0ms
qdisc netem 10: parent 1:1 limit 1000 delay 50.0ms

Ingress (ifb0):
qdisc tbf 1: root refcnt 2 rate 10Mbit burst 4Kb lat 400.0ms
qdisc netem 10: parent 1:1 limit 1000 delay 50.0ms
```

### 3. テストを実行

```bash
# クイックテスト（2回の反復）
make test-router-quick

# または、フルテスト
make test-router
```

### 4. 結果を確認

```bash
ls -lh test-results/
```

テスト結果がJSON形式で保存されています。

### 5. 停止

```bash
make down-router
```

## 📊 従来方式（Pumba）との比較

```bash
make compare-router-pumba
```

Router Pod版とPumba版の両方でテストを実行し、結果を比較できます。

**予想される違い:**
- **Router Pod**: Download速度が約10Mbpsに制限される（正しい挙動）
- **Pumba**: Download速度が30Mbps以上になる（問題のある挙動）

## ⚙️ カスタマイズ

### 帯域を変更

#### 方法1: 環境変数で指定

```bash
# 全ノード2Mbpsで起動
BANDWIDTH_RATE=2mbit make up-router

# 全ノード100Mbpsで起動
BANDWIDTH_RATE=100mbit make up-router
```

#### 方法2: .env.routerファイルを編集

```bash
# .env.routerを編集
vim .env.router

# 例: 全ノード5Mbps、遅延100ms
BANDWIDTH_RATE=5mbit
NETWORK_DELAY=100ms

# 起動
make up-router
```

#### 方法3: ノードごとに個別設定

```bash
# .env.routerを編集
vim .env.router

# Org1だけ高速回線
ORG1_BANDWIDTH_RATE=100mbit
ORG1_NETWORK_DELAY=20ms

# Org2は標準
ORG2_BANDWIDTH_RATE=10mbit
ORG2_NETWORK_DELAY=50ms

# Org3は低速
ORG3_BANDWIDTH_RATE=2mbit
ORG3_NETWORK_DELAY=100ms

# 起動
make up-router
```

### パケットロスを追加

```bash
# 2%のパケットロスを追加
PACKET_LOSS=2 make up-router
```

## 🔍 トラブルシューティング

### TC設定が表示されない

```bash
# コンテナのログを確認
docker logs ipfs-org1

# 以下のようなメッセージがあるはずです：
# ✓ Egress rate limit: 10mbit, delay: 50ms
# ✓ Ingress rate limit: 10mbit, delay: 50ms
```

### ifbモジュールエラー

ホストでifbモジュールを読み込んでください：

```bash
# Linux
sudo modprobe ifb numifbs=10

# macOS/Windows (Docker Desktop)
# 自動的に処理されます
```

### コンテナが起動しない

```bash
# ログを確認
make logs-router

# または個別に確認
docker logs ipfs-org1
```

## 📖 詳細ドキュメント

- [Router Pod Architecture 詳細](docs/router-pod-architecture.md)
- [使い方ガイド](docs/router-pod-usage.md)
- [帯域制限の問題点と解決策](docs/bandwidth-limitation-analysis.md)

## ❓ よくある質問

**Q: 既存のテストスクリプトは使えますか？**
A: はい、そのまま使えます。`make test-router-quick`を実行してください。

**Q: Pumbaは必要ですか？**
A: いいえ、Router Pod版ではPumbaは不要です。

**Q: 既存のdocker-compose.ymlと共存できますか？**
A: はい、別ファイル（docker-compose-router.yml）なので共存できます。

**Q: どちらが正確ですか？**
A: Router Pod版の方が現実のインターネット環境を正確にシミュレートします。

## 🎯 推奨される使い方

1. **開発中**: Router Pod版で正確なテスト
2. **CI/CD**: Router Pod版で自動テスト
3. **研究**: Router Pod版で実験データ収集
4. **デモ**: Pumba版でも可（簡易的）

## 🔗 関連コマンド

```bash
# ヘルプを表示
make help

# ネットワークステータス確認
make check-router

# ログをリアルタイム表示
make logs-router

# TC設定を確認
make check-tc
```
