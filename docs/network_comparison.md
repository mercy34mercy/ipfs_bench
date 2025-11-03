# Docker Composeネットワーク構成の比較

## 概要

IPFSベンチマークシステムで使用している「Single Router構成」と、通常の「Simple Bridge構成」の違いを、OSIモデルの各レイヤーで比較します。

---

## アーキテクチャ比較

### 1. Simple Bridge構成（通常のDocker Compose）

```
┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐
│ipfs-bench│  │ipfs-org1 │  │ipfs-org2 │  │ipfs-org3~│
└────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘
     │             │             │             │
     └─────────────┴─────────────┴─────────────┘
                   │
            ┌──────▼──────┐
            │Docker Bridge│ ← 全コンテナが同じL2セグメント
            │172.18.0.0/16│
            └──────┬──────┘
                   │
            ┌──────▼──────┐
            │ Host NIC    │ → Internet
            └─────────────┘
```

**特徴**:
- 全コンテナが**1つのBridge**に接続
- **Layer 2で直接通信**可能
- ルーター不要
- 外部アクセス可能（NAT経由）

### 2. Single Router構成（本プロジェクト）

```
┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐
│ipfs-bench│  │ipfs-org1 │  │ipfs-org2 │  │ipfs-org3~│
└────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘
     │             │             │             │
  bridge1       bridge2       bridge3       bridge4...
 (100.0/24)     (1.0/24)      (2.0/24)     (3.0/24)
     │             │             │             │
     └─────────────┴─────────────┴─────────────┘
                   │
            ┌──────▼────────┐
            │ Router        │ ← Layer 3ルーティング
            │ (Alpine)      │    + TC帯域幅制限
            │ 11 interfaces │
            └───────────────┘
```

**特徴**:
- 各コンテナが**独立したBridge**に接続
- **Layer 3ルーティング**が必要
- 全通信がRouterコンテナ経由
- **TC（Traffic Control）**で帯域幅制限
- `internal: true`で外部隔離

---

## レイヤー別の詳細比較

### Layer 7: アプリケーション層

| 項目 | Simple Bridge | Single Router |
|------|---------------|---------------|
| IPFS Kubo | 同じ | 同じ |
| HTTP API | 同じ | 同じ |
| Bitswap | 同じ | 同じ |
| 通信効率 | 高速 | 高速（パイプライン処理） |

**差異**: なし（アプリケーション層では同じ）

---

### Layer 4: トランスポート層

| 項目 | Simple Bridge | Single Router |
|------|---------------|---------------|
| TCP/UDP | 同じ | 同じ |
| ポート | :5001, :4001, :8080 | :5001, :4001, :8080 |
| コネクション管理 | カーネルが処理 | カーネルが処理 |

**差異**: なし（トランスポート層でも同じ）

---

### Layer 3: ネットワーク層

| 項目 | Simple Bridge | Single Router |
|------|---------------|---------------|
| サブネット | 1つ（172.18.0.0/16） | 11個（172.31.0-10.0/24） |
| IPアドレス | 172.18.0.10-20 | 172.31.1.10, 2.10, ... |
| ルーティング | 不要（同一セグメント） | **必須**（Router経由） |
| IP Forwarding | なし | **有効**（sysctl） |
| ルーティングテーブル | なし | **10+ルート** |

**差異**: ★★★ **大きな違い**

#### Simple Bridge: ルーティング不要

```bash
# ipfs-benchのルーティングテーブル
$ docker exec ipfs-bench ip route
172.18.0.0/16 dev eth0  # 同一セグメント、直接到達可能
default via 172.18.0.1   # デフォルトゲートウェイ
```

#### Single Router: 複雑なルーティング

```bash
# ipfs-benchのルーティングテーブル
$ docker exec ipfs-bench ip route
172.31.100.0/24 dev eth0
default via 172.31.100.1  # Routerがゲートウェイ

# Routerのルーティングテーブル
$ docker exec router ip route
172.31.1.0/24 dev eth1     # ipfs-org1へ
172.31.2.0/24 dev eth2     # ipfs-org2へ
172.31.3.0/24 dev eth3     # ipfs-org3へ
...
172.31.100.0/24 dev eth0   # ipfs-benchへ
```

---

### Layer 2: データリンク層

| 項目 | Simple Bridge | Single Router |
|------|---------------|---------------|
| Bridgeデバイス数 | **1個** | **11個** |
| Bridge名 | br-docker0（自動） | br-xxxxx1-11（自動） |
| セグメント | 同一L2セグメント | **11個の独立セグメント** |
| 直接通信 | **可能** | **不可**（Router経由） |
| internal:true | なし | **あり**（org1-10） |
| MACアドレス | 02:42:ac:12:00:xx | 02:42:ac:1f:xx:0a |
| ARP | 同一セグメント | 各セグメント独立 |

**差異**: ★★★ **根本的な違い**

#### Simple Bridge: 1つのL2スイッチ

```
全コンテナ ──┬── Bridge (br-docker0)
             │   ├─ MAC Table
             │   ├─ 02:42:ac:12:00:0a → veth-bench
             │   ├─ 02:42:ac:12:00:0b → veth-org1
             │   └─ 02:42:ac:12:00:0c → veth-org2
```

**通信例**（bench → org1）:
1. benchがARP: "172.18.0.11のMACは？"
2. org1が応答: "02:42:ac:12:00:0b"
3. benchがEthernet Frame送信: dst=02:42:ac:12:00:0b
4. **Bridge がスイッチング** → org1へ直接転送
5. org1が受信

→ **Layer 2だけで完結**

#### Single Router: 複数の独立L2セグメント + L3ルーティング

```
ipfs-bench ── Bridge1 (bench_net)     172.31.100.0/24
                │
ipfs-org1  ── Bridge2 (org1_net)      172.31.1.0/24
                │
ipfs-org2  ── Bridge3 (org2_net)      172.31.2.0/24
                │
              ...
                │
            ┌───┴───┐
            │Router │ ← 全Bridgeに接続
            └───────┘
```

**通信例**（bench → org1）:
1. benchが送信: dst=172.31.1.10
2. ルーティング: 172.31.1.0/24 via 172.31.100.1
3. **Bridge1** → Router eth0
4. Router: IP Forwarding処理
5. Router: ルーティングテーブル参照 → eth1
6. **Bridge2** ← Router eth1
7. org1が受信

→ **Layer 3ルーティング必須**

---

### Traffic Control (TC)

| 項目 | Simple Bridge | Single Router |
|------|---------------|---------------|
| TC設定場所 | 各コンテナ個別 | **Routerで一元管理** |
| 帯域幅制限 | 困難 | **容易** |
| Egress制限 | 可能 | **TBF実装済** |
| Ingress制限 | 困難 | **IFB実装済** |
| 制御粒度 | コンテナ単位 | **インターフェース単位** |

**差異**: ★★★ **Single Routerの主要機能**

#### Simple Bridge: TC設定困難

```bash
# 各コンテナで個別設定が必要
docker exec ipfs-org1 tc qdisc add dev eth0 root tbf rate 100mbit
docker exec ipfs-org2 tc qdisc add dev eth0 root tbf rate 100mbit
docker exec ipfs-org3 tc qdisc add dev eth0 root tbf rate 100mbit
...

# 問題点:
# - Ingressは直接制御できない
# - 全コンテナで同じ設定を繰り返す必要
# - 一元管理が不可能
```

#### Single Router: 一元管理可能

```bash
# Routerで全インターフェース一括設定
docker exec router tc qdisc add dev eth1 root tbf rate 100mbit burst 10mbit latency 1ms
docker exec router tc qdisc add dev eth2 root tbf rate 100mbit burst 10mbit latency 1ms
...

# スクリプトで動的変更可能
bash ./scripts/network-chaos/limit-bandwidth-routers.sh 1gbit

# 利点:
# - Egress/Ingress両方制御可能
# - 全ノードの帯域幅を一括変更
# - ベンチマークに最適
```

---

### Layer 1: 物理層

| 項目 | Simple Bridge | Single Router |
|------|---------------|---------------|
| 物理NIC接続 | **可能**（NAT経由） | **bench_netのみ** |
| インターネット | アクセス可能 | org1-10は不可 |
| external | true（デフォルト） | org1-10はfalse |

---

## 通信経路の比較

### Upload: ipfs-bench → ipfs-org1

#### Simple Bridge

```
【Layer 7】 HTTP POST /api/v0/add
   ↓
【Layer 4】 TCP :5001
   ↓
【Layer 3】 172.18.0.10 → 172.18.0.11（同一サブネット）
   ↓
【Layer 2】 Bridge経由で直接転送
           MAC: bench → org1
   ↓
【Layer 2】 Bridgeがスイッチング
   ↓
【受信】 ipfs-org1

総ホップ数: 1ホップ（L2のみ）
```

#### Single Router

```
【Layer 7】 HTTP POST /api/v0/add
   ↓
【Layer 4】 TCP :5001
   ↓
【Layer 3】 172.31.100.10 → 172.31.1.10（異なるサブネット）
   ↓
【Layer 2】 bench_net bridge → Router eth0
   ↓
【Router】 IP Forwarding: eth0 → eth1
   ↓
【TC】     帯域幅制限（100mbit）
   ↓
【Layer 2】 Router eth1 → ipfs_org1_net bridge
   ↓
【受信】 ipfs-org1

総ホップ数: 2ホップ（L2 → L3 → L2）
```

**所要時間**:
- Simple Bridge: 高速（L2直接）
- Single Router: やや遅い（L3ルーティング + TC処理）

---

### Download: ipfs-bench → ipfs-org2 → ipfs-org1 → ipfs-org2 → ipfs-bench

#### Simple Bridge（理論値）

```
ステップ1: bench → org2 (L2直接)
ステップ2: org2 → org1 (L2直接、Bitswap)
ステップ3: org1 → org2 (L2直接、ストリーミング)
ステップ4: org2 → bench (L2直接、ストリーミング)

総ホップ数: 4ホップ（全てL2）
理論時間: パイプライン処理で約1.1x
```

#### Single Router（実測）

```
ステップ1: bench → router → org2
ステップ2: org2 → router → org1 (Bitswap)
ステップ3: org1 → router → org2 (ストリーミング)
ステップ4: org2 → router → bench (ストリーミング)

総ホップ数: 8ホップ（各通信で2ホップ）
実測時間: 約1.18x（パイプライン処理 + 全二重）
```

**所要時間**:
- Simple Bridge: 理論的には最速
- Single Router: 意外にも1.18xで高効率

**理由**:
- IPFSのパイプライン処理
- 全二重Ethernet（送受信独立）
- TC制御のオーバーヘッドは18%のみ

---

## ユースケース別の選択

### Simple Bridge構成が適している場合

✓ **開発環境**
- 高速な通信が必要
- ネットワーク制御不要
- シンプルな構成

✓ **本番環境（小規模）**
- コンテナ間が信頼できる
- 外部アクセスが必要
- 複雑な設定を避けたい

✓ **マイクロサービス**
- サービス間通信が頻繁
- レイテンシが重要
- ネットワーク分離不要

---

### Single Router構成が適している場合

✓ **ベンチマーク環境**（本プロジェクト）
- 帯域幅制限が必要
- 遅延・パケットロスのシミュレーション
- ネットワーク性能測定

✓ **ネットワーク実験**
- 様々なネットワーク条件をテスト
- QoS（Quality of Service）検証
- プロトコル性能評価

✓ **セキュリティ重視**
- コンテナ間を厳密に分離
- 通信を一元監視
- `internal: true`で外部遮断

✓ **マルチテナント環境**
- テナント毎にネットワーク分離
- 帯域幅を公平に分配
- トラフィック監視

---

## パフォーマンス比較

### レイテンシ（ping RTT）

| 経路 | Simple Bridge | Single Router |
|------|---------------|---------------|
| bench → org1 | ~0.05ms | ~0.2ms |
| bench → org2 → org1 | ~0.1ms | ~0.4ms |

**理由**: L3ルーティング + TC処理のオーバーヘッド

---

### スループット（1GB転送）

| 項目 | Simple Bridge | Single Router (100Mbps) | Single Router (1Gbps) |
|------|---------------|-------------------------|----------------------|
| Upload | ~10Gbps | 95 Mbps | 1070 Mbps |
| Download | ~10Gbps | 91 Mbps | 860 Mbps |

**Simple Bridge**: TC制限なしで物理NICの限界まで
**Single Router**: TC制限により正確に制御可能

---

### CPU使用率

| コンポーネント | Simple Bridge | Single Router |
|---------------|---------------|---------------|
| Dockerd | 低 | 中 |
| カーネルネットワーク | 低 | 中 |
| Router Container | - | 高（TC処理） |

**Single Router**はRouterコンテナでCPU使用が増加するが、ベンチマークの精度が向上。

---

## docker-compose.yml の違い

### Simple Bridge

```yaml
version: "3.8"

services:
  ipfs-bench:
    image: ipfs-bench:latest
    networks:
      - ipfs_network  # 全コンテナが同じnetwork
    ports:
      - "5001:5001"

  ipfs-org1:
    image: ipfs/kubo:latest
    networks:
      - ipfs_network  # 同じnetwork

  ipfs-org2:
    image: ipfs/kubo:latest
    networks:
      - ipfs_network  # 同じnetwork

networks:
  ipfs_network:
    driver: bridge
    ipam:
      config:
        - subnet: 172.18.0.0/16  # 1つの大きなサブネット
```

### Single Router

```yaml
version: "3.8"

services:
  router:
    image: alpine:latest
    cap_add:
      - NET_ADMIN
    sysctls:
      - net.ipv4.ip_forward=1
    networks:
      - bench_net        # 11個のnetworkに接続
      - ipfs_org1_net
      - ipfs_org2_net
      # ...

  ipfs-bench:
    networks:
      bench_net:
        ipv4_address: 172.31.100.10

  ipfs-org1:
    networks:
      ipfs_org1_net:     # 独立したnetwork
        ipv4_address: 172.31.1.10

  ipfs-org2:
    networks:
      ipfs_org2_net:     # 独立したnetwork
        ipv4_address: 172.31.2.10

networks:
  bench_net:
    driver: bridge
    ipam:
      config:
        - subnet: 172.31.100.0/24

  ipfs_org1_net:
    driver: bridge
    internal: true       # 外部隔離
    ipam:
      config:
        - subnet: 172.31.1.0/24

  ipfs_org2_net:
    driver: bridge
    internal: true
    ipam:
      config:
        - subnet: 172.31.2.0/24
```

---

## まとめ

### Simple Bridge構成

**メリット**:
- ✅ シンプルで理解しやすい
- ✅ 高速（L2直接通信）
- ✅ 低レイテンシ
- ✅ 外部アクセス可能

**デメリット**:
- ❌ 帯域幅制限が困難
- ❌ ネットワーク分離なし
- ❌ TC制御が複雑

**適用**: 開発環境、小規模本番、マイクロサービス

---

### Single Router構成

**メリット**:
- ✅ 帯域幅制限が容易
- ✅ 一元的なTC管理
- ✅ ネットワーク分離
- ✅ ベンチマーク精度

**デメリット**:
- ❌ 複雑な構成
- ❌ やや高レイテンシ
- ❌ CPUオーバーヘッド
- ❌ 設定が煩雑

**適用**: ベンチマーク、ネットワーク実験、セキュリティ重視、マルチテナント

---

## 関連ドキュメント

- [Single Router構成図](./docker_network_layers.drawio)
- [Simple Bridge構成図](./docker_simple_bridge.drawio)
- [ネットワークレイヤー詳細解説](./network_layers_explained.md)
- [IPFS性能分析](./ipfs_performance_analysis.md)

---

**作成日**: 2025-10-27
**バージョン**: 1.0
