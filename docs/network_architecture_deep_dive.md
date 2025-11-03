# Dockerネットワークアーキテクチャ詳細解説

## 目次

1. [veth pairとBridgeの関係](#veth-pairとbridgeの関係)
2. [L2↔L3変換の必然性](#l2l3変換の必然性)
3. [Simple Bridge構成でのTC制御の困難さ](#simple-bridge構成でのtc制御の困難さ)
4. [Single Router構成を選んだ理由](#single-router構成を選んだ理由)
5. [まとめ](#まとめ)

---

## veth pairとBridgeの関係

### よくある誤解

**Q: Simple Bridge構成では、Bridgeなしでvethで直接MACアドレス通信できるのでは？**

**A: いいえ、Bridgeは必須です。**

### veth pairの仕組み

veth (Virtual Ethernet) は**必ずペア**で動作します：

```
┌─────────────────────┐         ┌─────────────────────┐
│  Container Namespace│         │  Host Namespace     │
│                     │         │                     │
│     eth0            │◄───────►│   vethXXXXX         │
│  (container側)      │  pair   │   (host側)          │
└─────────────────────┘         └─────────────────────┘
```

**重要な制約**: このペアは**2つのインターフェース間でのみ通信可能**

### 複数コンテナ間の通信

```
Container A:  eth0-A  ◄─── pair ───►  vethAAAA (Host)
Container B:  eth0-B  ◄─── pair ───►  vethBBBB (Host)
Container C:  eth0-C  ◄─── pair ───►  vethCCCC (Host)
```

**問題点**:
- vethAAAA と vethBBBB は**異なるネットワークデバイス**
- Linux kernelでは異なるインターフェース間は直接通信できない
- L2フレームを転送する**スイッチング機能**が必要

### Bridgeの必然性

#### Bridgeなしの場合（❌ 通信不可）

```
┌──────────┐              ┌──────────┐
│Container │              │Container │
│    A     │              │    B     │
│  eth0-A  │              │  eth0-B  │
└────┬─────┘              └────┬─────┘
     │ veth pair              │ veth pair
     ↓                        ↓
┌────┴─────┐              ┌────┴─────┐
│ vethAAAA │              │ vethBBBB │
│  (Host)  │    ✗✗✗      │  (Host)  │
└──────────┘  直接通信不可  └──────────┘
```

#### Bridgeありの場合（✅ 通信可能）

```
┌──────────┐              ┌──────────┐
│Container │              │Container │
│    A     │              │    B     │
│  eth0-A  │              │  eth0-B  │
└────┬─────┘              └────┬─────┘
     │ veth pair              │ veth pair
     ↓                        ↓
┌────┴─────┐              ┌────┴─────┐
│ vethAAAA │              │ vethBBBB │
│  (Host)  │              │  (Host)  │
└────┬─────┘              └────┬─────┘
     │                        │
     └────────┬───────────────┘
              │
        ┌─────▼──────┐
        │   Bridge   │ ← L2スイッチング
        │ (br-XXXXX) │    MAC Table保持
        └────────────┘
```

### 実際の確認方法

```bash
# Dockerネットワーク作成
docker network create test-net
docker run -d --name test1 --network test-net alpine sleep infinity

# veth確認
ip link show | grep veth
# 出力: 123: veth8a2b3c4@if122: <BROADCAST,MULTICAST,UP>

# Bridge配下のインターフェース確認
docker network inspect test-net | grep BridgeID
# 出力: "com.docker.network.bridge.name": "br-abc123def456"

# vethがBridgeに接続されていることを確認
ip link show master br-abc123def456
# 出力: 123: veth8a2b3c4@if122: <BROADCAST,MULTICAST,UP> master br-abc123def456
#                                                          ↑
#                                                    Bridgeのポート
```

### Linux Bridge = L2スイッチ

Bridgeが提供する機能：

1. **MACアドレス学習**
   ```bash
   # MACテーブル確認
   bridge fdb show br br-abc123def456
   # 出力:
   # 02:42:ac:12:00:02 dev veth8a2b3c4 master br-abc123def456
   # 02:42:ac:12:00:03 dev veth9d4e5f6 master br-abc123def456
   ```

2. **ユニキャスト転送**
   - dst MACが既知 → 該当ポートのみに転送

3. **ブロードキャスト/フラッディング**
   - dst MAC = FF:FF:FF:FF:FF:FF → 全ポートに転送

4. **ポート状態管理**
   ```bash
   bridge link show
   # 出力: 123: veth8a2b3c4@if122: state forwarding
   #                                      ↑
   #                              L2スイッチのポート状態
   ```

### パケット転送の流れ

```
1. Container A から Container B へパケット送信
   eth0-A: dst MAC = 02:42:ac:12:00:03 (Container B)

2. veth pair経由でHost側へ
   veth8a2b3c4 が受信

3. Bridge がMACテーブルを参照
   02:42:ac:12:00:03 → veth9d4e5f6 に転送すべき
   ↑
   これがなければ通信不可！

4. Bridge が veth9d4e5f6 へ転送

5. veth pair経由でContainer Bへ
   eth0-B で受信
```

### 結論

- **Bridgeは必須**: vethだけでは複数コンテナ間通信は不可能
- **Simple Bridgeの"Simple"**: Single Routerと比べて構成がシンプルという意味
- **どちらの構成でもBridgeは必要**: 違いはBridgeの数（1個 vs 11個）

---

## L2↔L3変換の必然性

### よくある疑問

**Q: L2からL3に変換して、また L2に戻すのはよくあること？**

**A: はい、これがルーターの正常な動作です。むしろこれが世界標準です。**

### ルーターの基本動作

```
送信側コンテナ:
┌─────────────────────────────────────┐
│ L7: HTTP データ                      │
│ L4: TCP ヘッダー追加                 │
│ L3: IP ヘッダー追加 (src/dst IP)    │
│ L2: Ethernet ヘッダー追加 (MAC)      │ ← カプセル化
└─────────────────────────────────────┘
              ↓ L2転送
        Bridge (L2)
              ↓
┌─────────────────────────────────────┐
│         Router受信側                 │
│ 1. L2フレーム受信                    │
│ 2. L2ヘッダー削除 ─────┐           │ ← デカプセル化
│ 3. L3パケット取り出し   │           │
│ 4. ルーティング判定     │ (L3処理) │
│ 5. 新しいL2ヘッダー付与 │           │ ← 再カプセル化
└─────────────────────────────────────┘
              ↓ L2転送
        Bridge (L2)
              ↓
受信側コンテナ:
┌─────────────────────────────────────┐
│ L2: Ethernet ヘッダー削除            │
│ L3: IP ヘッダー確認                  │
│ L4: TCP処理                          │
│ L7: HTTPデータ取り出し               │ ← デカプセル化
└─────────────────────────────────────┘
```

### 実世界の例

#### 1. 家庭のインターネット接続

```
あなたのPC (192.168.1.10)
  ↓ L2: WiFi Ethernet
家庭用ルーター (192.168.1.1)
  ↓ L3: ルーティング処理 ← ここでL2→L3→L2
  ↓ L2: PPPoE (新しいL2!)
ISP ネットワーク
  ↓ L3: 複数のルーターでホップ ← 各ルーターでL2→L3→L2
  ↓ L2: 光ファイバー、MPLS等
Googleサーバー (8.8.8.8)
```

**何度もL2↔L3変換が発生！**

#### 2. 企業ネットワーク（VLAN）

```
社内PC (VLAN 10: 172.16.10.5)
  ↓ L2: Ethernet (VLAN tag 10)
L2スイッチ
  ↓ L2: VLAN転送
L3スイッチ/ルーター
  ↓ L3: VLAN間ルーティング (10 → 20) ← L2→L3→L2
  ↓ L2: Ethernet (VLAN tag 20)
L2スイッチ
  ↓ L2: VLAN転送
サーバー (VLAN 20: 172.16.20.10)
```

#### 3. 東京から大阪へパケット送信

```
東京のPC (Ethernet)
  ↓ L2: Ethernet, MAC: AA:BB:CC:DD:EE:FF
東京のルーター
  ↓ L3: ルーティング判定 (宛先: 大阪)
  ↓ L2: 光ファイバー, MAC: 11:22:33:44:55:66 ← 変わった！
ISP骨格ネットワーク
  ↓ L3: 複数ルーター経由
  ↓ L2: MPLS ラベル
大阪のルーター
  ↓ L3: ルーティング判定
  ↓ L2: Ethernet, MAC: 99:88:77:66:55:44 ← また変わった！
大阪のPC
```

**重要な原則**:
- **L3のIPアドレスは変わらない**（送信元〜最終目的地まで）
- **L2のMACアドレスは各ホップで変わる**

### なぜこの設計なのか？

#### レイヤーの責任分離

| Layer | 役割 | スコープ |
|-------|------|---------|
| L2 | 同一ネットワーク内の転送 | MACアドレス、直接接続されたデバイス |
| L3 | 異なるネットワーク間のルーティング | IPアドレス、全世界 |

**基本原則**:
- L2だけでは異なるネットワークに届かない
- L3だけでは物理的に送信できない
- **両方必要**

### Routerコンテナで確認

```bash
# パケットキャプチャでL2ヘッダーを確認
docker exec router tcpdump -i eth1 -e -n icmp

# 出力例:
# 02:42:ac:1f:01:0a > 02:42:ac:1f:01:01  ← L2 (src MAC > dst MAC)
# IP 172.31.1.10 > 172.31.100.10         ← L3 (src IP > dst IP)
```

#### eth1で受信したパケット

- **L2 src**: ipfs-org1のMAC (02:42:ac:1f:01:0a)
- **L2 dst**: Router eth1のMAC (02:42:ac:1f:01:01)
- **L3 src**: 172.31.1.10 (変わらない)
- **L3 dst**: 172.31.100.10 (変わらない)

#### eth0から送信するパケット

- **L2 src**: Router eth0のMAC (02:42:ac:1f:64:01) ← **変わった！**
- **L2 dst**: ipfs-benchのMAC (02:42:ac:1f:64:0a) ← **変わった！**
- **L3 src**: 172.31.1.10 (変わらない)
- **L3 dst**: 172.31.100.10 (変わらない)

### インターネット全体がこの仕組み

- 世界中のルーターが毎秒何億回もL2↔L3変換している
- AWS VPC、Google Cloud、Kubernetesも同様
- これがOSIモデルの「レイヤー分離」の本質

### 結論

**L2→L3→L2変換は**:
- ✅ よくある（むしろ標準）
- ✅ ルーターの基本動作
- ✅ インターネットの根幹
- ✅ 本プロジェクトは現実のネットワークを正確に模擬

---

## Simple Bridge構成でのTC制御の困難さ

### 核心的な疑問

**Q: 技術的にはL2でもL3でも100Mbpsの帯域幅制限はできるはず。Simple Bridge構成でもTC制御できるのでは？**

**A: 技術的には可能ですが、実装・管理が非常に困難です。**

### 方法1: 各コンテナでTC設定

```yaml
# docker-compose.yml
services:
  ipfs-org1:
    image: ipfs/kubo:latest
    cap_add:
      - NET_ADMIN  # TC制御に必要
    entrypoint:
      - /bin/sh
      - -c
      - |
        # Egress（送信）制限
        tc qdisc add dev eth0 root tbf rate 100mbit burst 10mbit latency 1ms

        # Ingress（受信）制限は困難
        # modprobe ifb  ← コンテナ内では権限不足
        # ip link add ifb0 type ifb  ← 失敗

        # 結局Egressのみ
        exec ipfs daemon

  ipfs-org2:
    # 同じ設定を繰り返し...
    cap_add:
      - NET_ADMIN
    entrypoint:
      - /bin/sh
      - -c
      - |
        tc qdisc add dev eth0 root tbf rate 100mbit burst 10mbit latency 1ms
        exec ipfs daemon

  ipfs-org3:
    # また同じ設定を繰り返し...

  # ... ipfs-org4 ~ org10も同様
```

#### 問題点

| 問題 | 詳細 |
|------|------|
| ❌ **Ingress制御不可** | コンテナ内でIFBデバイスが作れない |
| ❌ **設定の重複** | 10個のコンテナで同じ設定を繰り返す |
| ❌ **動的変更不可** | 帯域幅変更にはコンテナ再起動が必要 |
| ❌ **保守性が低い** | 設定変更時に全コンテナを更新 |

#### なぜIngress制御が困難か

```bash
# コンテナ内でIFBを作ろうとすると...
docker exec ipfs-org1 sh -c "
  modprobe ifb
  ip link add ifb0 type ifb
  ip link set ifb0 up
"

# エラー:
# modprobe: can't change directory to '/lib/modules': No such file
# RTNETLINK answers: Operation not permitted
```

**原因**:
- コンテナはHost kernelモジュールにアクセスできない
- ネットワークデバイス作成は特権が必要
- `--privileged`を付けても、kernelモジュールは共有されない

#### 実験結果

```bash
# ipfs-org1でEgress制限のみ設定
docker exec ipfs-org1 tc qdisc add dev eth0 root tbf rate 100mbit burst 10mbit latency 1ms

# ✅ アップロード（Egress）
docker exec ipfs-bench ipfs add large-file
# 結果: 約100Mbps → 制限が効いている

# ❌ ダウンロード（Ingress）
docker exec ipfs-bench ipfs cat QmXXX > /dev/null
# 結果: 約1Gbps → 制限が効いていない！
```

### 方法2: Bridgeデバイスで制限

```bash
# Host上で実行
tc qdisc add dev br-abc123def456 root tbf rate 100mbit burst 10mbit latency 1ms
```

#### 問題点

- ❌ **全コンテナが同じ100Mbpsを共有**してしまう
- ❌ コンテナAとBが同時通信すると、各50Mbpsになる
- ❌ 個別制御が不可能

```
Bridge: 100Mbps制限
   ├── Container A: 使用中 → 70Mbps
   ├── Container B: 使用中 → 20Mbps
   └── Container C: 使用中 → 10Mbps
       ↑
   合計で100Mbps、個別制御不可
```

### 方法3: vethデバイスで個別制限

```bash
# 各vethに個別設定
tc qdisc add dev veth8a2b3c4 root tbf rate 100mbit burst 10mbit latency 1ms
tc qdisc add dev veth9d4e5f6 root tbf rate 100mbit burst 10mbit latency 1ms
# ... 10個繰り返し
```

#### 問題点

```bash
# veth名を調べる
docker exec ipfs-org1 cat /sys/class/net/eth0/iflink
# 出力: 123

ip link | grep "^123:"
# 出力: 123: veth8a2b3c4@if122: <BROADCAST,MULTICAST,UP>
```

**問題**:
- ❌ veth名がDocker自動生成で**予測不可能**
- ❌ コンテナ再起動で**veth名が変わる**
- ❌ docker-compose.ymlで自動化できない
- ❌ 手動設定が必要

### 方法4: Host側でIFB設定（最も複雑）

```bash
# 各コンテナのvethにIFB設定（Host側スクリプト）
for i in {1..10}; do
  VETH=$(docker exec ipfs-org$i cat /sys/class/net/eth0/iflink)
  VETH_NAME=$(ip link | grep "^${VETH}:" | awk '{print $2}' | cut -d'@' -f1)

  # IFB作成
  ip link add ifb$i type ifb
  ip link set ifb$i up

  # Ingress → IFB リダイレクト
  tc qdisc add dev $VETH_NAME handle ffff: ingress
  tc filter add dev $VETH_NAME parent ffff: protocol ip \
    matchall action mirred egress redirect dev ifb$i

  # IFBで帯域幅制限
  tc qdisc add dev ifb$i root tbf rate 100mbit burst 10mbit latency 1ms
done
```

#### 問題点

- ❌ docker-compose.ymlに組み込めない
- ❌ 外部スクリプトが必要
- ❌ コンテナ再起動で再設定が必要
- ❌ 自動化が極めて困難

### 比較表

| 項目 | Simple Bridge + TC | Single Router |
|------|-------------------|---------------|
| **Egress制御** | ⚠️ 可能（各コンテナ） | ✅ 容易（Router） |
| **Ingress制御** | ❌ 困難（IFB作成不可） | ✅ 容易（IFB設定済） |
| **一元管理** | ❌ 不可能 | ✅ 可能 |
| **動的変更** | ❌ コンテナ再起動必要 | ✅ スクリプトで即変更 |
| **個別制限** | ❌ 困難 | ✅ 各インターフェース独立 |
| **設定の再現性** | ❌ 低い | ✅ 高い |
| **docker-compose統合** | ❌ 困難 | ✅ 完全統合 |

---

## Single Router構成を選んだ理由

### 設計目標

IPFSベンチマークシステムで必要な要件：

1. ✅ **正確な帯域幅制限** (Egress + Ingress)
2. ✅ **動的な帯域幅変更** (10Mbps ↔ 1Gbps)
3. ✅ **一元管理** (1箇所で全ノード制御)
4. ✅ **再現性** (同じ条件で繰り返しテスト)
5. ✅ **自動化** (スクリプトで完結)

### Single Router構成の実装

```yaml
version: "3.8"

services:
  # ========================================
  # 中央ルーター（すべての通信を制御）
  # ========================================
  router:
    image: alpine:latest
    cap_add:
      - NET_ADMIN
    sysctls:
      - net.ipv4.ip_forward=1
    environment:
      BANDWIDTH_RATE: ${BANDWIDTH_RATE:-100mbit}
    volumes:
      - ./setup-router-single.sh:/setup-router-single.sh
    command: /bin/sh /setup-router-single.sh
    networks:
      - bench_net
      - ipfs_org1_net
      - ipfs_org2_net
      # ... org3-10
    restart: unless-stopped

  # ========================================
  # IPFSノード（TC設定不要！）
  # ========================================
  ipfs-org1:
    image: ipfs/kubo:latest
    # ← cap_add不要、TC設定不要
    networks:
      ipfs_org1_net:
        ipv4_address: 172.31.1.10

  ipfs-org2:
    image: ipfs/kubo:latest
    networks:
      ipfs_org2_net:
        ipv4_address: 172.31.2.10

  # ... すべてシンプル

networks:
  bench_net:
    driver: bridge
    ipam:
      config:
        - subnet: 172.31.100.0/24

  ipfs_org1_net:
    driver: bridge
    internal: true  # 外部隔離
    ipam:
      config:
        - subnet: 172.31.1.0/24

  # ... 各ノードに独立したネットワーク
```

### Routerの初期化スクリプト

```bash
#!/bin/sh
# setup-router-single.sh

# 全インターフェースを取得
INTERFACES=$(ip -o link show | awk -F': ' '{print $2}' | grep '^eth' | cut -d'@' -f1)

# 帯域幅の自動計算
RATE_MBPS=$(echo $BANDWIDTH_RATE | sed 's/mbit//' | sed 's/gbit/000/')
if [ $RATE_MBPS -ge 1000 ]; then
    BURST="100mbit"
elif [ $RATE_MBPS -ge 100 ]; then
    BURST="10mbit"
elif [ $RATE_MBPS -ge 10 ]; then
    BURST="1mbit"
else
    BURST="100kbit"
fi
LATENCY="1ms"

# 各インターフェースにTC設定
for IFACE in $INTERFACES; do
    IFB_DEV="ifb${IFACE#eth}"

    # IFBデバイス作成
    ip link add $IFB_DEV type ifb
    ip link set $IFB_DEV up

    # Egress制限
    tc qdisc add dev $IFACE root tbf rate $BANDWIDTH_RATE burst $BURST latency $LATENCY

    # Ingress制限（IFB経由）
    tc qdisc add dev $IFACE handle ffff: ingress
    tc filter add dev $IFACE parent ffff: protocol ip \
      matchall action mirred egress redirect dev $IFB_DEV
    tc qdisc add dev $IFB_DEV root tbf rate $BANDWIDTH_RATE burst $BURST latency $LATENCY
done

# ルーターとして動作
sleep infinity
```

### 動的な帯域幅変更

```bash
#!/bin/bash
# scripts/network-chaos/limit-bandwidth-routers.sh

BANDWIDTH_RATE=$1  # 例: 1gbit

# Routerコンテナ内で実行
docker exec router sh -c "
  for IFACE in \$(ip -o link show | awk -F': ' '{print \$2}' | grep '^eth'); do
    # 既存のqdisc削除
    tc qdisc del dev \$IFACE root 2>/dev/null
    tc qdisc del dev \$IFACE ingress 2>/dev/null

    IFB_DEV=\"ifb\${IFACE#eth}\"
    tc qdisc del dev \$IFB_DEV root 2>/dev/null

    # 新しい帯域幅で再設定
    tc qdisc add dev \$IFACE root tbf rate $BANDWIDTH_RATE burst $BURST latency $LATENCY
    tc qdisc add dev \$IFACE handle ffff: ingress
    tc filter add dev \$IFACE parent ffff: protocol ip matchall action mirred egress redirect dev \$IFB_DEV
    tc qdisc add dev \$IFB_DEV root tbf rate $BANDWIDTH_RATE burst $BURST latency $LATENCY
  done
"

echo "✓ Bandwidth updated to $BANDWIDTH_RATE"
```

**使い方**:
```bash
# ベンチマーク実行中でも変更可能
bash ./scripts/network-chaos/limit-bandwidth-routers.sh 10mbit
bash ./scripts/network-chaos/limit-bandwidth-routers.sh 100mbit
bash ./scripts/network-chaos/limit-bandwidth-routers.sh 1gbit
```

### 利点のまとめ

| 利点 | 説明 |
|------|------|
| ✅ **一元管理** | Routerコンテナのみで全制御 |
| ✅ **Egress + Ingress** | IFBで双方向制限 |
| ✅ **動的変更** | コンテナ再起動不要 |
| ✅ **再現性** | docker-compose.ymlで完全定義 |
| ✅ **シンプルなIPFSノード** | cap_add不要、TC設定不要 |
| ✅ **スクリプト化** | 完全自動化可能 |
| ✅ **ネットワーク分離** | `internal: true`で外部遮断 |

### 実測結果

```bash
# 100Mbps設定
bash ./scripts/network-chaos/limit-bandwidth-routers.sh 100mbit

# アップロード
make test-router
# 結果: 約95Mbps ✅ Egress制限

# ダウンロード
# 結果: 約91Mbps ✅ Ingress制限

# 1Gbps設定
bash ./scripts/network-chaos/limit-bandwidth-routers.sh 1gbit

# アップロード
# 結果: 約1070Mbps ✅

# ダウンロード
# 結果: 約860Mbps ✅
```

### ベンチマークワークフロー

```bash
# 1. 環境起動
make up-router

# 2. ピア接続
bash ./scripts/connect-ipfs-peers.sh

# 3. 帯域幅設定
bash ./scripts/network-chaos/limit-bandwidth-routers.sh 100mbit

# 4. テスト実行
make test-router

# 5. 帯域幅変更（コンテナ起動したまま）
bash ./scripts/network-chaos/limit-bandwidth-routers.sh 1gbit

# 6. 再テスト
make test-router

# 7. グラフ生成
python3 ./scripts/generate_graphs.py
```

---

## まとめ

### Q1: vethで直接通信できる？

**A: いいえ、Bridgeが必須です。**

- veth pairは2点間通信のみ
- 複数コンテナ間の通信にはL2スイッチ（Bridge）が必要
- Simple BridgeもSingle Routerも、両方ともBridgeを使用

### Q2: L2→L3→L2変換はよくあること？

**A: はい、これがルーターの基本動作で世界標準です。**

- インターネット全体がこの仕組み
- 各ホップでL2ヘッダーは変わるが、L3ヘッダー（IP）は変わらない
- OSIモデルのレイヤー分離の本質

### Q3: Simple Bridge構成でもTC制御は可能？

**A: 技術的には可能ですが、実装・管理が非常に困難です。**

| 制約 | Simple Bridge + TC | Single Router |
|------|-------------------|---------------|
| Egress制限 | ⚠️ 可能だが各コンテナ設定必要 | ✅ Router一元管理 |
| Ingress制限 | ❌ IFB作成不可 | ✅ IFB設定済 |
| 動的変更 | ❌ 再起動必要 | ✅ スクリプトで即変更 |
| 自動化 | ❌ 極めて困難 | ✅ 完全自動化 |

### 設計選択の理由

**Simple Bridge構成が適している場合**:
- 開発環境
- 高速通信が重要
- ネットワーク制御不要
- シンプルさ重視

**Single Router構成が適している場合**（本プロジェクト）:
- ✅ ベンチマーク環境
- ✅ 正確な帯域幅制限が必要
- ✅ 様々なネットワーク条件をテスト
- ✅ 再現性が重要
- ✅ 一元管理が必要

### 最終的な答え

**「Docker ComposeでTC制御が無理」ではなく、「Simple Bridge構成でTC制御が実用的でない」**

Single Router構成は：
- 技術的制約の回避策ではなく
- ベンチマークに最適化された設計選択
- 現実のネットワークを正確に模擬
- 管理性と再現性を最大化

---

## 関連ドキュメント

- [Single Router構成図](./docker_network_layers.drawio)
- [Simple Bridge構成図](./docker_simple_bridge.drawio)
- [ネットワーク構成比較](./network_comparison.md)
- [ネットワークレイヤー詳細](./network_layers_explained.md)
- [IPFS性能分析](./ipfs_performance_analysis.md)

---

**作成日**: 2025-10-27
**バージョン**: 1.0
**カテゴリ**: ネットワークアーキテクチャ、Docker、TC制御
