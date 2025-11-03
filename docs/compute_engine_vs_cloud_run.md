# IPFSベンチマークに最適なクラウドサービス: Compute Engine vs Cloud Run

## 結論: Compute Engine (VM) 一択

IPFSノードのベンチマークには、**Compute Engine（GCP）や EC2（AWS）などのVMサービスを使うべき**です。

Cloud Run や AWS Fargate のようなサーバーレスコンテナサービスは**研究・ベンチマーク用途には不向き**です。

## Cloud Run / Fargate が不向きな理由

### 1. リソースの不透明性

**Cloud Run:**

```yaml
問題点:
- CPUの種類が不明（Intel? AMD? Arm?）
- 実際の物理コアなのか vCPU なのか不明
- メモリの実装詳細が不明
- ネットワークスタックが抽象化されている
```

**影響:**
- 再現性がない（実行ごとに異なるハードウェア）
- ベンチマーク結果の信頼性が低い
- 論文や研究レポートに書けない

### 2. ネットワーク制御の制限

**Cloud Run の制限:**

```bash
# これができない
tc qdisc add dev eth0 root tbf rate 10mbit ...

# 理由
- NET_ADMIN capability がない
- コンテナの権限が制限されている
- カーネルモジュールにアクセスできない
```

**つまり:**
- 帯域幅制限ができない
- レイテンシの追加ができない
- パケットロスのシミュレーションができない
- **既存の tc ベースのスクリプトが使えない**

### 3. 永続的な接続の問題

**Cloud Run の制約:**

```yaml
制限:
- リクエストベースのモデル
- アイドル時にコールドスタート
- 最大タイムアウト: 60分（3600秒）
- 同時接続数の制限
```

**IPFSノードへの影響:**
- P2Pの永続的な接続が維持できない
- DHT（分散ハッシュテーブル）の構築が困難
- ピア発見が不安定
- 長時間のベンチマークができない

### 4. ポートの制限

**Cloud Run:**

```yaml
制限:
- HTTPSポート（443）のみ公開可能
- カスタムポートが使えない
```

**IPFSが必要とするポート:**

```yaml
IPFS デフォルトポート:
- 4001: Swarm（P2P通信）← TCP/UDP 必須
- 5001: API
- 8080: Gateway（HTTP）

Cloud Run では 4001 が開けない！
```

### 5. コストの不透明性

**Cloud Run の課金:**

```yaml
課金要素:
- リクエスト数
- CPU時間
- メモリ使用量
- ネットワーク転送量

問題:
- 長時間実行のコストが予測困難
- アイドル時間も課金される場合がある
- スケールアップ/ダウンで不安定
```

### 6. デバッグの困難さ

**Cloud Run:**

```bash
# SSH できない
ssh user@cloud-run-instance  # ← 不可能

# ログしか見れない
gcloud logs read --limit 50 --format json

# ネットワークのデバッグができない
ip link show  # ← 実行不可
tc qdisc show dev eth0  # ← 実行不可
```

## Compute Engine (VM) が最適な理由

### 1. 完全な制御

**できること:**

```bash
# 任意のカーネルモジュールのロード
modprobe ifb

# tc コマンドの実行
tc qdisc add dev ens4 root tbf rate 10mbit ...

# 任意のポートの開放
iptables -A INPUT -p tcp --dport 4001 -j ACCEPT

# システムパラメータの調整
sysctl -w net.core.rmem_max=2500000
```

### 2. リソースの透明性

**VM インスタンス:**

```yaml
例: n1-standard-2
- CPU: Intel Xeon（世代も選択可能）
- vCPU: 2（物理コア数も明示）
- メモリ: 7.5 GB
- ネットワーク: 10 Gbps

→ すべて明確！論文に書ける！
```

### 3. 永続的な実行

**制限なし:**

```yaml
実行時間: 無制限
- 数時間でも、数日でも OK
- IPFSノードとして永続的に稼働
- P2P接続を維持
- DHTの構築が可能
```

### 4. ネットワークの柔軟性

**完全な制御:**

```yaml
ファイアウォール:
- 任意のポートを開放可能（4001, 5001, 8080）
- UDP/TCP どちらも対応

外部IP:
- 静的IPアドレスの割り当て可能
- グローバルIPFSネットワークへの参加が容易
```

### 5. 既存環境の互換性

**既存プロジェクトがそのまま動く:**

```bash
# VM に SSH
ssh user@vm-instance

# リポジトリをクローン
git clone https://github.com/your-repo/ipfs_bench.git
cd ipfs_bench

# 既存のスクリプトを実行
docker-compose up -d

# tc を使った帯域幅制限もそのまま動く
./container-init/setup-router-tc.sh
```

### 6. デバッグの容易さ

**SSH でフルアクセス:**

```bash
# SSH ログイン
ssh user@vm-instance

# リアルタイムでログ確認
docker logs -f ipfs-node

# ネットワークの状態確認
ip link show
tc qdisc show dev ens4

# IPFS のデバッグ
docker exec ipfs-node ipfs swarm peers
docker exec ipfs-node ipfs id
```

### 7. コストの透明性

**シンプルな課金:**

```yaml
GCP Compute Engine:
- インスタンス料金: $0.095/時間（n1-standard-2）
- ディスク: $0.040/GB/月（標準）
- ネットワーク: $0.12/GB（エグレス）

→ 計算しやすい！
```

**例: 8時間のベンチマーク**

```
インスタンス: $0.095 × 8時間 × 4台 = $3.04
ディスク: 30GB × 4台 × $0.04 ÷ 30日 = $0.16
ネットワーク: 50GB × $0.12 = $6.00
合計: 約 $9.20

→ 予測可能！
```

### 8. 研究・論文向き

**Compute Engine のメリット:**

```yaml
論文に書けること:
- "Intel Xeon E5-2690 v3 @ 2.60GHz"
- "2 vCPUs (2 physical cores)"
- "Ubuntu 22.04 LTS, Linux kernel 5.15"
- "tc を使用して 10 Mbps に制限"

再現性:
- 他の研究者が同じ環境を構築可能
- インスタンスタイプが明確
- OSやカーネルバージョンも明示
```

## サービス比較表

| 項目 | Compute Engine / EC2 | Cloud Run / Fargate |
|------|---------------------|---------------------|
| **CPU/メモリの透明性** | ✅ 明確 | ❌ 不明 |
| **ネットワーク制御（tc）** | ✅ 可能 | ❌ 不可 |
| **任意ポート開放** | ✅ 可能（4001等） | ❌ HTTPSのみ |
| **永続的な実行** | ✅ 無制限 | ❌ 最大60分 |
| **SSH アクセス** | ✅ 可能 | ❌ 不可 |
| **カーネルモジュール** | ✅ ロード可能 | ❌ 不可 |
| **既存スクリプト互換性** | ✅ そのまま動く | ❌ 修正必要 |
| **P2P 接続維持** | ✅ 可能 | ⚠️ 困難 |
| **コスト予測** | ✅ 容易 | ⚠️ 複雑 |
| **研究・論文向き** | ✅ 最適 | ❌ 不向き |
| **セットアップの簡単さ** | ⚠️ 要SSH | ✅ 簡単 |
| **スケーリング** | ⚠️ 手動 | ✅ 自動 |

## 推奨構成

### GCP での推奨

**Compute Engine インスタンス:**

```yaml
マシンタイプ: n1-standard-2 または n2-standard-2
- vCPU: 2
- メモリ: 7.5 GB
- OS: Ubuntu 22.04 LTS

ディスク:
- タイプ: 標準永続ディスク
- サイズ: 30 GB

ネットワーク:
- 外部IP: エフェメラル（または静的）
- ファイアウォール: 4001, 5001, 8080 を開放
```

**コスト（東京リージョン、8時間）:**

```
オンデマンド: 約 $3
プリエンプティブ: 約 $0.64
```

### AWS での推奨

**EC2 インスタンス:**

```yaml
インスタンスタイプ: t3.medium または t3a.medium
- vCPU: 2
- メモリ: 4 GB
- OS: Ubuntu 22.04 LTS

ストレージ:
- タイプ: gp3
- サイズ: 30 GB

ネットワーク:
- パブリックIP: 自動割り当て
- セキュリティグループ: 4001, 5001, 8080 を開放
```

**コスト（東京リージョン、8時間）:**

```
オンデマンド: 約 $1.33
スポット: 約 $0.38
```

## 実装手順（GCP Compute Engine）

### ステップ1: インスタンスの作成

```bash
# gcloud CLI で作成
gcloud compute instances create ipfs-bench-1 \
  --machine-type=n1-standard-2 \
  --zone=asia-northeast1-a \
  --image-family=ubuntu-2204-lts \
  --image-project=ubuntu-os-cloud \
  --boot-disk-size=30GB \
  --tags=ipfs-node

# ファイアウォールルールの作成
gcloud compute firewall-rules create allow-ipfs \
  --allow=tcp:4001,tcp:5001,tcp:8080,udp:4001 \
  --target-tags=ipfs-node
```

### ステップ2: セットアップ

```bash
# SSH でログイン
gcloud compute ssh ipfs-bench-1 --zone=asia-northeast1-a

# Docker のインストール
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
newgrp docker

# リポジトリのクローン
git clone https://github.com/your-repo/ipfs_bench.git
cd ipfs_bench

# 既存のスクリプトを実行
docker-compose up -d
```

### ステップ3: ネットワーク制限の適用

```bash
# 既存のスクリプトを使用
export BANDWIDTH_RATE="10mbit"
export NETWORK_DELAY="50ms"
export PACKET_LOSS="1"

sudo ./container-init/setup-router-tc.sh
```

### ステップ4: ベンチマークの実行

```bash
# 既存のベンチマークスクリプト
./run_bench_10nodes.sh
```

## Cloud Run が向いているケース

**以下の場合のみ検討:**

1. **HTTPベースの軽量なテスト**
   - IPFSゲートウェイのHTTPアクセステスト
   - 短時間の負荷テスト

2. **P2P機能を使わない場合**
   - ゲートウェイ経由のファイル取得のみ
   - DHT不要

3. **ネットワーク制限が不要な場合**
   - 理想的な環境でのテスト
   - 最大性能の測定

**しかし、これらのケースでも Compute Engine の方が柔軟です。**

## まとめ

### IPFSベンチマークには Compute Engine / EC2

**理由:**

1. ✅ **完全な制御**: tc コマンド、カーネルモジュール、任意のポート
2. ✅ **透明性**: CPU/メモリ/ネットワークが明確
3. ✅ **既存環境との互換性**: スクリプトがそのまま動く
4. ✅ **永続的な実行**: P2P接続の維持が可能
5. ✅ **研究向き**: 再現性があり、論文に書ける
6. ✅ **デバッグ容易**: SSH でフルアクセス
7. ✅ **コスト透明**: 予測しやすい

### Cloud Run / Fargate は不向き

**理由:**

1. ❌ ネットワーク制御（tc）ができない
2. ❌ リソースが不透明
3. ❌ P2P接続の維持が困難
4. ❌ 任意のポートが開けない
5. ❌ 研究・ベンチマーク用途に不適切

### 次のステップ

1. **クラウドプラットフォームの選択**: GCP or AWS
2. **Compute Engine / EC2 インスタンスの起動**
3. **既存プロジェクトのデプロイ**（そのまま動く！）
4. **ベンチマークの実行**

**追加開発は不要** - 既存の VM ベースの実装がそのまま使えます！
