# Router Pod アーキテクチャ - 現実的なネットワーク環境の再現

## 問題の本質

現在のアプローチの根本的な問題は、**IPFSノードが直接通信してしまう**ことです。

### 通常のIPFS通信構造

```
[ IPFS Node A ] ⇄ [ IPFS Node B ]
    (直接P2P通信)
```

- 各ノードがlibp2pを使ってP2P接続を確立
- どちらもポートを開けて、NAT越え・DHT経由で直接通信
- Docker上では、同じbridgeネットワーク内なら内部IPで直結

**結果:** 帯域や遅延はホストや仮想ネットワーク任せで、**細かく制御できない**

### 現在の帯域制限アプローチの限界

```
Docker Network
  ├── ipfs-bench (pumba: egress制限のみ)
  ├── ipfs-org1 (pumba: egress制限のみ)
  ├── ipfs-org2 (pumba: egress制限のみ)
  └── ipfs-org3 (pumba: egress制限のみ)
```

**問題点:**
1. ❌ Pumbaではingress制限ができない
2. ❌ 直接tc qdiscを使うのは煩雑
3. ❌ 各ノードが「独立したネット回線」を持っている感じにならない
4. ❌ 現実の家庭ルータ的な挙動を再現できない

---

## 解決策: Router Pod アーキテクチャ

### コンセプト

**各IPFSノードに専用のルータを配置し、すべての通信をルータ経由にする**

これにより、各ノードが「独自の家庭回線を持っている」状態を再現できます。

### アーキテクチャ図

```
                   ┌────────────┐
                   │  Internet  │
                   │ (Simulated)│
                   └─────┬──────┘
                         │
         ┌───────────────┼───────────────┐
         │               │               │
   ┌─────────┐     ┌─────────┐     ┌─────────┐
   │ routerA │     │ routerB │     │ routerC │
   │ tc/ifb  │     │ tc/ifb  │     │ tc/ifb  │
   │ 10Mbps  │     │ 10Mbps  │     │ 10Mbps  │
   │ 50ms    │     │ 50ms    │     │ 50ms    │
   └────┬────┘     └────┬────┘     └────┬────┘
        │               │               │
   ┌────┴────┐     ┌────┴────┐     ┌────┴────┐
   │ ipfs-   │     │ ipfs-   │     │ ipfs-   │
   │  org1   │     │  org2   │     │  org3   │
   └─────────┘     └─────────┘     └─────────┘
```

### 動作原理

1. **各IPFSノード** (`ipfs-org1`, `ipfs-org2`, `ipfs-org3`) は専用の**Router Pod**を経由して通信
2. **Router Pod内**で`tc`（Traffic Control）と`ifb`（Intermediate Functional Block）を使用
3. **egress（送信）とingress（受信）の両方**を制限可能
4. 外部への接続も他ノードとのP2Pも、**すべてRouter経由**

---

## 技術詳細

### tc + ifb による双方向帯域制限

#### Egress（送信）制限

```bash
# eth0の送信を10Mbpsに制限
tc qdisc add dev eth0 root tbf rate 10mbit burst 32kbit latency 400ms
```

#### Ingress（受信）制限

Linuxのtcでは、ingressを直接制限できないため、**ifb（Intermediate Functional Block）**を使用：

```bash
# ifbモジュールをロード
modprobe ifb

# ifb0デバイスを作成
ip link add ifb0 type ifb
ip link set ifb0 up

# eth0の受信トラフィックをifb0にリダイレクト
tc qdisc add dev eth0 handle ffff: ingress
tc filter add dev eth0 parent ffff: protocol ip u32 match u32 0 0 \
  action mirred egress redirect dev ifb0

# ifb0の送信（=元のeth0の受信）を10Mbpsに制限
tc qdisc add dev ifb0 root tbf rate 10mbit burst 32kbit latency 400ms
```

**仕組み:**
1. eth0に到着したパケット（ingress）をifb0にリダイレクト
2. ifb0のegress（送信）として制限
3. 結果的にeth0のingressが制限される

---

## Docker Compose実装例

### 基本構成（1ノード分）

```yaml
version: "3.9"

services:
  router-org1:
    image: alpine:latest
    container_name: router-org1
    cap_add:
      - NET_ADMIN
    command: >
      sh -c "
        apk add --no-cache iproute2 &&
        modprobe ifb &&
        ip link add ifb0 type ifb &&
        ip link set ifb0 up &&

        # Egress制限（送信）
        tc qdisc add dev eth0 root tbf rate 10mbit burst 32kbit latency 400ms &&

        # Ingress制限（受信）
        tc qdisc add dev eth0 handle ffff: ingress &&
        tc filter add dev eth0 parent ffff: protocol ip u32 match u32 0 0 \
          action mirred egress redirect dev ifb0 &&
        tc qdisc add dev ifb0 root tbf rate 10mbit burst 32kbit latency 400ms &&

        echo 'Router configured with 10Mbps bidirectional limit' &&
        tail -f /dev/null
      "
    networks:
      ipfs_network:
        ipv4_address: 172.28.1.2

  ipfs-org1:
    image: ipfs/kubo:latest
    container_name: ipfs-org1
    depends_on:
      - router-org1
    environment:
      IPFS_PATH: /data/ipfs
    volumes:
      - ./data/ipfs-org1:/data/ipfs
    command: ["daemon", "--migrate=true"]
    networks:
      ipfs_network:
        ipv4_address: 172.28.1.3
    # すべての通信をrouter経由にする
    sysctls:
      - net.ipv4.ip_forward=1

networks:
  ipfs_network:
    driver: bridge
    ipam:
      config:
        - subnet: 172.28.0.0/16
```

### 完全な3ノード構成

```yaml
version: "3.9"

services:
  # ========================================
  # Organization 1: Router + IPFS
  # ========================================
  router-org1:
    image: alpine:latest
    container_name: router-org1
    cap_add:
      - NET_ADMIN
    command: >
      sh -c "
        apk add --no-cache iproute2 &&
        modprobe ifb &&
        ip link add ifb0 type ifb &&
        ip link set ifb0 up &&
        tc qdisc add dev eth0 root tbf rate 10mbit burst 32kbit latency 400ms &&
        tc qdisc add dev eth0 handle ffff: ingress &&
        tc filter add dev eth0 parent ffff: protocol ip u32 match u32 0 0 \
          action mirred egress redirect dev ifb0 &&
        tc qdisc add dev ifb0 root tbf rate 10mbit burst 32kbit latency 400ms &&
        echo 'Router-org1: 10Mbps configured' &&
        tail -f /dev/null
      "
    networks:
      ipfs_network:
        ipv4_address: 172.28.1.2

  ipfs-org1:
    image: ipfs/kubo:latest
    container_name: ipfs-org1
    depends_on:
      - router-org1
    environment:
      IPFS_PATH: /data/ipfs
    volumes:
      - ./data/ipfs-org1:/data/ipfs
    command: ["daemon", "--migrate=true"]
    networks:
      ipfs_network:
        ipv4_address: 172.28.1.3

  # ========================================
  # Organization 2: Router + IPFS
  # ========================================
  router-org2:
    image: alpine:latest
    container_name: router-org2
    cap_add:
      - NET_ADMIN
    command: >
      sh -c "
        apk add --no-cache iproute2 &&
        modprobe ifb &&
        ip link add ifb0 type ifb &&
        ip link set ifb0 up &&
        tc qdisc add dev eth0 root tbf rate 10mbit burst 32kbit latency 400ms &&
        tc qdisc add dev eth0 handle ffff: ingress &&
        tc filter add dev eth0 parent ffff: protocol ip u32 match u32 0 0 \
          action mirred egress redirect dev ifb0 &&
        tc qdisc add dev ifb0 root tbf rate 10mbit burst 32kbit latency 400ms &&
        echo 'Router-org2: 10Mbps configured' &&
        tail -f /dev/null
      "
    networks:
      ipfs_network:
        ipv4_address: 172.28.2.2

  ipfs-org2:
    image: ipfs/kubo:latest
    container_name: ipfs-org2
    depends_on:
      - router-org2
    environment:
      IPFS_PATH: /data/ipfs
    volumes:
      - ./data/ipfs-org2:/data/ipfs
    command: ["daemon", "--migrate=true"]
    networks:
      ipfs_network:
        ipv4_address: 172.28.2.3

  # ========================================
  # Organization 3: Router + IPFS
  # ========================================
  router-org3:
    image: alpine:latest
    container_name: router-org3
    cap_add:
      - NET_ADMIN
    command: >
      sh -c "
        apk add --no-cache iproute2 &&
        modprobe ifb &&
        ip link add ifb0 type ifb &&
        ip link set ifb0 up &&
        tc qdisc add dev eth0 root tbf rate 10mbit burst 32kbit latency 400ms &&
        tc qdisc add dev eth0 handle ffff: ingress &&
        tc filter add dev eth0 parent ffff: protocol ip u32 match u32 0 0 \
          action mirred egress redirect dev ifb0 &&
        tc qdisc add dev ifb0 root tbf rate 10mbit burst 32kbit latency 400ms &&
        echo 'Router-org3: 10Mbps configured' &&
        tail -f /dev/null
      "
    networks:
      ipfs_network:
        ipv4_address: 172.28.3.2

  ipfs-org3:
    image: ipfs/kubo:latest
    container_name: ipfs-org3
    depends_on:
      - router-org3
    environment:
      IPFS_PATH: /data/ipfs
    volumes:
      - ./data/ipfs-org3:/data/ipfs
    command: ["daemon", "--migrate=true"]
    networks:
      ipfs_network:
        ipv4_address: 172.28.3.3

  # ========================================
  # Benchmark Client
  # ========================================
  router-bench:
    image: alpine:latest
    container_name: router-bench
    cap_add:
      - NET_ADMIN
    command: >
      sh -c "
        apk add --no-cache iproute2 &&
        modprobe ifb &&
        ip link add ifb0 type ifb &&
        ip link set ifb0 up &&
        tc qdisc add dev eth0 root tbf rate 10mbit burst 32kbit latency 400ms &&
        tc qdisc add dev eth0 handle ffff: ingress &&
        tc filter add dev eth0 parent ffff: protocol ip u32 match u32 0 0 \
          action mirred egress redirect dev ifb0 &&
        tc qdisc add dev ifb0 root tbf rate 10mbit burst 32kbit latency 400ms &&
        echo 'Router-bench: 10Mbps configured' &&
        tail -f /dev/null
      "
    networks:
      ipfs_network:
        ipv4_address: 172.28.100.2

  ipfs-bench:
    build: .
    container_name: ipfs-bench
    depends_on:
      - router-bench
      - ipfs-org1
      - ipfs-org2
      - ipfs-org3
    volumes:
      - ./:/app
      - ./results:/app/results
    environment:
      BENCHMARK_MODE: "true"
    networks:
      ipfs_network:
        ipv4_address: 172.28.100.3

networks:
  ipfs_network:
    driver: bridge
    ipam:
      config:
        - subnet: 172.28.0.0/16
```

---

## メリット

| 項目 | Router Pod経由の利点 |
|------|---------------------|
| **帯域制御** | ✅ 各ノードごとに10Mbpsや1Mbpsを正確に再現可能 |
| **双方向制限** | ✅ Egress（送信）とIngress（受信）の両方を制限 |
| **遅延・ロス制御** | ✅ DHT・Bitswapのレイテンシ特性を再現可能 |
| **分離性** | ✅ 実際のNAT挙動（家庭ルータ的）もシミュレート可能 |
| **柔軟性** | ✅ ノードごとに異なるネットワーク品質を付与可能 |
| **現実性** | ✅ 実際の家庭回線環境を正確にシミュレート |

---

## 従来アプローチとの比較

| 項目 | Pumba netem | tc qdisc直接 | **Router Pod** |
|------|------------|-------------|---------------|
| Egress制限 | ✅ 可能 | ✅ 可能 | ✅ 可能 |
| Ingress制限 | ❌ 不可 | ⚠️ 複雑 | ✅ 可能 |
| 遅延制御 | ✅ 可能 | ✅ 可能 | ✅ 可能 |
| パケットロス | ✅ 可能 | ✅ 可能 | ✅ 可能 |
| 設定の簡潔さ | ✅ 簡単 | ❌ 煩雑 | ✅ 簡単 |
| 現実性 | ⚠️ 低い | ⚠️ 低い | ✅ **高い** |
| ノード独立性 | ❌ なし | ❌ なし | ✅ **完全独立** |

---

## 実験応用例

### 1. 研究用途（ZKや分散台帳）

```yaml
# 異なる帯域のノード構成
router-fast:   20mbit (先進国の回線)
router-medium: 10mbit (一般的な回線)
router-slow:   2mbit  (途上国の回線)
```

→ ノード間の通信確率・ブロック伝搬速度を評価可能

### 2. IPFS-Clusterのスループット測定

```yaml
# ノード数をスケール
3ノード × 10Mbps
5ノード × 10Mbps
10ノード × 10Mbps
```

→ ノード数×帯域制限によるスケーリング実験

### 3. ネットワーク故障テスト

```bash
# 動的に帯域・遅延を変更
docker exec router-org1 tc qdisc change dev eth0 root netem delay 500ms loss 5%
```

→ フォールトトレランスを検証

### 4. 地理的分散シミュレーション

```yaml
# 地域別の遅延設定
router-us:     10mbit delay 20ms  (米国)
router-eu:     10mbit delay 100ms (欧州)
router-asia:   10mbit delay 200ms (アジア)
```

→ 地理的に分散したIPFSネットワークを再現

---

## 実装ステップ

### Phase 1: 基本構成の実装

- [ ] Router Pod用のDocker Composeファイル作成
- [ ] tc/ifb設定スクリプトの実装
- [ ] 1ノード構成でテスト

### Phase 2: 複数ノード対応

- [ ] 3ノード（ipfs-org1/2/3）の構成
- [ ] ipfs-benchノードの追加
- [ ] ノード間通信の確認

### Phase 3: 帯域制限テスト

- [ ] 各ノードの帯域制限が正しく動作することを確認
- [ ] 複数ノードから同時ダウンロード時の挙動確認
- [ ] Pumbaアプローチとの比較測定

### Phase 4: 高度な機能

- [ ] 動的な帯域変更スクリプト
- [ ] 遅延・パケットロスの追加
- [ ] ネットワーク品質のモニタリング

---

## 設定パラメータ例

### 一般的な家庭回線

```bash
# ADSL（遅い）
rate 2mbit burst 16kbit latency 400ms
netem delay 100ms

# 一般的な光回線
rate 10mbit burst 32kbit latency 400ms
netem delay 50ms

# 高速回線
rate 100mbit burst 64kbit latency 200ms
netem delay 20ms
```

### パケットロスの追加

```bash
# 1%のパケットロス
tc qdisc add dev eth0 root netem loss 1%

# 帯域制限とパケットロス併用
tc qdisc add dev eth0 root handle 1: tbf rate 10mbit burst 32kbit latency 400ms
tc qdisc add dev eth0 parent 1:1 handle 10: netem loss 1% delay 50ms
```

---

## まとめ

### 現在のアプローチの問題

- Pumbaではingress制限ができない
- tc qdiscを直接使うのは各コンテナで煩雑
- ノードが「独立したネット回線」を持っている感じにならない

### Router Pod アーキテクチャの解決

✅ **各ノードに専用ルータを配置**
✅ **Egress/Ingressの両方を制限可能**
✅ **現実の家庭回線環境を正確に再現**
✅ **柔軟なテスト環境の構築**

### 次のステップ

Router Pod アーキテクチャを実装することで、**現実的なIPFSネットワーク環境**を正確にシミュレートできます。

---

## 関連ドキュメント

- [帯域制限の問題点と解決策](./bandwidth-limitation-analysis.md) - 従来アプローチの分析
- [ネットワーク図](../network-bandwidth-diagram.drawio) - 視覚的な説明

---

## 参考リンク

- [Linux Traffic Control (tc) Documentation](https://man7.org/linux/man-pages/man8/tc.8.html)
- [IFB (Intermediate Functional Block) Device](https://wiki.linuxfoundation.org/networking/ifb)
- [IPFS libp2p Networking](https://docs.ipfs.tech/concepts/libp2p/)
