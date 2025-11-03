# なぜクラウドのネイティブ機能ではなく tc を使うのか？

## 結論: クラウドには細かい帯域幅制限機能がない

驚くかもしれませんが、**AWS も GCP も細かいネットワーク帯域幅制限をかける機能を提供していません**。

## クラウドが提供するネットワーク機能

### AWS で提供されるもの

#### 1. インスタンスタイプによる上限

```
t3.micro    → 最大 5 Gbps
t3.medium   → 最大 5 Gbps
m5.large    → 最大 10 Gbps
c5n.18xlarge → 100 Gbps
```

**問題点:**
- あくまで「最大値」で保証されない
- 細かい設定ができない（10 Mbps、100 Mbps に制限不可）
- インスタンスタイプを変えるとCPU/メモリも変わってしまう

#### 2. Security Groups / Network ACLs

```yaml
# できること
- ポートの開閉（22, 80, 443 など）
- IP アドレスの許可/拒否
- プロトコルの制御（TCP, UDP, ICMP）

# できないこと
- 帯域幅の制限
- レイテンシの追加
- パケットロスの設定
```

#### 3. VPC / Transit Gateway

```yaml
# できること
- ネットワークの分離
- ルーティング制御
- VPN/DirectConnect 接続

# できないこと
- 帯域幅の細かい制限
- QoS (Quality of Service) 設定
```

#### 4. AWS Global Accelerator / CloudFront

```yaml
# できること
- CDN による配信最適化
- DDoS 保護
- エッジロケーション経由のルーティング

# できないこと
- 意図的に帯域幅を制限する
- レイテンシを追加する
- パケットロスをシミュレート
```

**AWS で唯一それっぽいもの: Amazon CloudWatch Synthetics + AWS FIS (Fault Injection Simulator)**
- 主にカオスエンジニアリング用
- 高価（$1-10/実験）
- ベンチマーク用途には過剰スペック
- 結局内部では tc を使っている

### GCP で提供されるもの

#### 1. インスタンスタイプによる上限

```
n1-standard-1 → 2 Gbps
n1-standard-2 → 10 Gbps
n2-standard-4 → 16 Gbps
```

**AWS と同じ問題:**
- 細かい制御不可
- 保証されない

#### 2. Firewall Rules

```yaml
# AWS の Security Groups と同等
- ポート制御
- IP 制御
- プロトコル制御

# 帯域幅制限はできない
```

#### 3. VPC / Cloud Router

```yaml
# AWS と同等の機能
- ネットワーク分離
- ルーティング

# 帯域幅制限はできない
```

#### 4. Cloud CDN / Load Balancing

```yaml
# AWS CloudFront と同等
- CDN による最適化
- 負荷分散

# 帯域幅制限はできない
```

## なぜクラウドは帯域幅制限機能を提供しないのか？

### 理由1: ビジネスモデル

クラウドプロバイダーは**データ転送量で課金**しているため、ユーザーが帯域幅を制限する機能を提供するインセンティブがない。

```
AWS データ転送料金（東京リージョン）:
- 最初の 100 GB/月: $0.114/GB
- 次の 40 TB/月: $0.089/GB
- ...

→ たくさん使ってほしい！
```

### 理由2: 技術的複雑さ

細かい QoS 制御は:
- ハードウェアレベルの対応が必要
- 他のテナントへの影響の可能性
- マルチテナント環境での公平性の問題

### 理由3: ユースケースの少なさ

多くのユーザーは:
- **速くしたい**（制限したくない）
- コスト削減したい（転送量を減らす = アプリ最適化）

**意図的に遅くしたい**というユースケースは稀（ベンチマーク、テスト用途のみ）

## tc (Traffic Control) とは？

Linux カーネルに組み込まれた**ネットワークトラフィック制御機能**

### 何ができるか？

```bash
# 1. 帯域幅制限
tc qdisc add dev eth0 root tbf rate 10mbit burst 32kbit latency 400ms
→ 10 Mbps に制限

# 2. 遅延追加
tc qdisc add dev eth0 root netem delay 100ms 10ms
→ 100ms ± 10ms の遅延を追加

# 3. パケットロス
tc qdisc add dev eth0 root netem loss 1%
→ 1% のパケットをランダムにドロップ

# 4. 複雑な組み合わせ
tc qdisc add dev eth0 root handle 1: tbf rate 10mbit burst 32kbit latency 400ms
tc qdisc add dev eth0 parent 1:1 handle 10: netem delay 50ms loss 0.5%
→ 10 Mbps + 50ms 遅延 + 0.5% ロス
```

### なぜ tc が強力なのか？

1. **完全な制御**
   - 帯域幅を 1 Kbps 単位で制御可能
   - 遅延をミリ秒単位で設定
   - パケットロスを 0.1% 単位で設定

2. **無料**
   - Linux カーネルの機能
   - 追加コストなし

3. **柔軟性**
   - インターフェースごとに設定可能
   - プロトコルごとに制御可能（HTTP だけ遅く、など）
   - 時間帯で変更可能

4. **再現性**
   - 同じコマンドで同じ環境を再現
   - スクリプト化が容易

## tc の欠点

### 1. 学習コスト

```bash
# 複雑な構文
tc qdisc add dev eth0 root handle 1: htb default 12
tc class add dev eth0 parent 1: classid 1:1 htb rate 100mbit
tc class add dev eth0 parent 1:1 classid 1:10 htb rate 50mbit ceil 100mbit
tc class add dev eth0 parent 1:1 classid 1:12 htb rate 10mbit ceil 100mbit
```

**しかし**: このプロジェクトには既に完成したスクリプトがある！

### 2. OS レベルの操作が必要

- VM に SSH してコマンド実行
- または起動時スクリプト（user-data）で設定

**しかし**: これも既存のスクリプトで自動化されている

### 3. Ingress (受信) 制限が複雑

Egress（送信）は簡単だが、Ingress（受信）は IFB（Intermediate Functional Block）が必要:

```bash
# IFB デバイスの作成と設定
modprobe ifb
ip link add ifb0 type ifb
ip link set ifb0 up

# 受信トラフィックを IFB にリダイレクト
tc qdisc add dev eth0 handle ffff: ingress
tc filter add dev eth0 parent ffff: protocol ip u32 match u32 0 0 \
    action mirred egress redirect dev ifb0

# IFB で制限を適用
tc qdisc add dev ifb0 root tbf rate 10mbit burst 32kbit latency 400ms
```

**しかし**: このプロジェクトには既に実装済み！（setup-router-tc.sh）

## 既存プロジェクトの実装

### スクリプト1: setup-router-tc.sh

**場所:** `container-init/setup-router-tc.sh`

**機能:**
- ルーターコンテナでのネットワーク制限
- Egress/Ingress 両方向の制御
- 環境変数で簡単に設定変更

**使い方:**
```bash
export BANDWIDTH_RATE="10mbit"
export NETWORK_DELAY="50ms"
export PACKET_LOSS="1"
./container-init/setup-router-tc.sh
```

### スクリプト2: start-private-ipfs-with-tc.sh

**場所:** `container-init/start-private-ipfs-with-tc.sh`

**機能:**
- IPFS ノードごとのネットワーク制限
- IPFS デーモン起動前に tc を設定
- Docker コンテナ内で動作

**使い方:**
```yaml
# docker-compose.yml
services:
  ipfs-node:
    image: ipfs/go-ipfs
    cap_add:
      - NET_ADMIN  # tc コマンドに必要
    environment:
      - BANDWIDTH_RATE=10mbit
      - DELAY=50ms
      - PACKET_LOSS=1
    volumes:
      - ./container-init:/scripts
    command: /scripts/start-private-ipfs-with-tc.sh
```

## クラウドへの移行時の対応

### AWS EC2

```bash
#!/bin/bash
# user-data スクリプト

# Docker のインストール
curl -fsSL https://get.docker.com | sh

# リポジトリのクローン
git clone https://github.com/your-repo/ipfs_bench.git
cd ipfs_bench

# Docker Compose で起動（tc 設定込み）
docker-compose up -d

# または、VM 自体に tc を適用
tc qdisc add dev eth0 root tbf rate 10mbit burst 32kbit latency 400ms
```

**ポイント:**
- インターフェース名は `eth0` が一般的
- `NET_ADMIN` capability が必要
- 既存のスクリプトがそのまま動く

### GCP Compute Engine

```bash
#!/bin/bash
# startup-script

# Docker のインストール
curl -fsSL https://get.docker.com | sh

# リポジトリのクローン
git clone https://github.com/your-repo/ipfs_bench.git
cd ipfs_bench

# Docker Compose で起動
docker-compose up -d

# または、VM 自体に tc を適用
tc qdisc add dev ens4 root tbf rate 10mbit burst 32kbit latency 400ms
```

**ポイント:**
- インターフェース名は `ens4` が一般的（または `eth0`）
- AWS とほぼ同じ
- 既存のスクリプトがそのまま動く

## まとめ

### なぜ tc を使うのか？

| 項目 | クラウド機能 | Linux tc |
|------|-------------|----------|
| 細かい帯域幅制限 | ❌ 不可 | ✅ 1 Kbps 単位 |
| 遅延の追加 | ❌ 不可 | ✅ 1 ms 単位 |
| パケットロス | ❌ 不可 | ✅ 0.1% 単位 |
| 追加コスト | - | ✅ 無料 |
| 学習コスト | 低 | 高（だが既に実装済み！） |
| 移植性 | クラウド依存 | ✅ どこでも動く |

### このプロジェクトの強み

✅ **既に tc ベースの完成したスクリプトがある**
✅ **Egress/Ingress 両方向の制御が実装済み**
✅ **環境変数で簡単に設定変更可能**
✅ **Docker + tc の組み合わせで移植性が高い**

### クラウド移行時の注意点

1. **インターフェース名の確認**
   - AWS: 通常 `eth0`
   - GCP: 通常 `ens4`
   - スクリプトで `ip link show` して確認

2. **NET_ADMIN capability**
   - Docker コンテナ内で tc を使う場合は必須
   - `cap_add: - NET_ADMIN`

3. **iproute2 パッケージ**
   - ほとんどの Linux ディストリビューションに標準搭載
   - なければ `apt-get install iproute2` または `yum install iproute-tc`

## 次のステップ

既存の tc ベースの実装を活用して、クラウドでベンチマークを実行するだけです！

1. **クラウドプラットフォームの選択**（AWS or GCP）
2. **インスタンスの起動**（t3.medium または n1-standard-2）
3. **既存スクリプトの実行**（そのまま動く！）
4. **ベンチマーク実行**

**追加開発は不要** - 既存の資産がそのまま使えます！
