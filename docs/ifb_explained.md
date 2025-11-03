# IFB (Intermediate Functional Block) 詳細解説

## 目次
1. [IFBとは](#ifbとは)
2. [なぜIFBが必要なのか](#なぜifbが必要なのか)
3. [IFBの仕組み](#ifbの仕組み)
4. [実装方法](#実装方法)
5. [パケットの流れ](#パケットの流れ)
6. [今回のプロジェクトでの使用例](#今回のプロジェクトでの使用例)
7. [検証方法](#検証方法)
8. [トラブルシューティング](#トラブルシューティング)

---

## IFBとは

**IFB (Intermediate Functional Block)** は、Linuxカーネルが提供する**仮想ネットワークデバイス**です。

### 基本特性
- **実体**: カーネル内の仮想デバイス（物理インターフェースではない）
- **目的**: Ingressトラフィックに対してEgress制御を適用する
- **カーネルモジュール**: `ifb`（`modprobe ifb`でロード）
- **デバイス名**: `ifb0`, `ifb1`, `ifb2`...

### なぜ存在するのか？

Linuxカーネルの制約を回避するため：
- **Egress（送信）**: カーネルが送信キューを管理 → 帯域制限可能
- **Ingress（受信）**: パケットは外部から到着 → 帯域制限不可

→ **IFBを使って受信パケットを「送信」に変換する**

---

## なぜIFBが必要なのか

### TC (Traffic Control) の制限

#### ✅ Egress制御は簡単
```bash
# eth0から出ていくパケットを100Mbpsに制限
tc qdisc add dev eth0 root tbf rate 100mbit burst 32kbit latency 400ms
```

**仕組み**:
```
アプリ → カーネル送信キュー → [TC制御] → eth0 → 外部
                               ↑
                          ここで制御可能
```

#### ❌ Ingress制御は困難
```bash
# これではフィルタリングのみ（帯域制限できない）
tc qdisc add dev eth0 ingress
tc filter add dev eth0 parent ffff: protocol ip u32 match u32 0 0 drop
```

**問題**:
```
外部 → eth0 → [TC ingress] → カーネル受信キュー → アプリ
              ↑
         すでに届いている！
         遅くすることは不可能
```

パケットはすでにネットワークカードまで届いており、カーネルが「受信速度を遅くする」ことはできない。

### 従来の回避策（IFB以前）

1. **IMQ (Intermediate Queueing Device)**: カーネルパッチが必要（非標準）
2. **iptables MARK + 複雑なルーティング**: 設定が煩雑
3. **送信側で制限**: 受信側ではコントロール不可

→ **IFBは標準カーネルモジュールで実現可能**

---

## IFBの仕組み

### コンセプト：受信を送信に変換

```
                  ┌─────────────────────────────────┐
外部からパケット到着│                                 │
                  │                                 │
      ┌───────────▼────────┐                       │
      │  eth0 Ingress      │                       │
      │  (制御不可)         │                       │
      └───────────┬────────┘                       │
                  │                                 │
                  │ tc filter action mirred         │
                  │ redirect                        │
                  │                                 │
      ┌───────────▼────────┐                       │
      │  IFB0 (仮想デバイス)│                       │
      │                    │                       │
      │  ┌──────────────┐  │                       │
      │  │ Egress Queue │  │  ← ここで制限可能！   │
      │  │  (TBF 100M)  │  │                       │
      │  └──────────────┘  │                       │
      └───────────┬────────┘                       │
                  │                                 │
      ┌───────────▼────────┐                       │
      │ カーネル受信処理    │                       │
      │ (ip_rcv → TCP/IP)  │                       │
      └───────────┬────────┘                       │
                  │                                 │
                  ▼                                 │
              アプリケーション                       │
                                                    │
                  └─────────────────────────────────┘
```

### キーポイント

1. **リダイレクト**: eth0のIngressパケットをIFBにリダイレクト
2. **送信扱い**: IFBではパケットが「Egress」として扱われる
3. **制御可能**: EgressなのでTBF/HTBなどで帯域制限可能
4. **透過的**: アプリケーションからは見えない（カーネル内部処理）

---

## 実装方法

### ステップ1: IFBモジュールのロード

```bash
# IFBモジュールをロード（デバイス2個作成）
modprobe ifb numifbs=2

# 確認
ip link show type ifb
# 出力:
# 2: ifb0: <BROADCAST,NOARP> mtu 1500 qdisc noop state DOWN
# 3: ifb1: <BROADCAST,NOARP> mtu 1500 qdisc noop state DOWN
```

### ステップ2: IFBデバイスを起動

```bash
ip link set ifb0 up
ip link set ifb1 up

# 確認
ip link show ifb0
# 出力:
# 2: ifb0: <BROADCAST,NOARP,UP,LOWER_UP> mtu 1500 qdisc pfifo_fast ...
```

### ステップ3: Ingressからリダイレクト

```bash
# eth0のIngress設定
tc qdisc add dev eth0 ingress

# すべてのパケットをifb0にリダイレクト
tc filter add dev eth0 parent ffff: \
    protocol ip \
    u32 match u32 0 0 \
    action mirred egress redirect dev ifb0
```

**解説**:
- `parent ffff:`: Ingress qdisc（固定のハンドル番号）
- `u32 match u32 0 0`: すべてのパケットにマッチ
- `action mirred egress redirect`: パケットをifb0のEgressに転送

### ステップ4: IFBで帯域制限

```bash
# ifb0のEgressに100Mbps制限を適用
tc qdisc add dev ifb0 root tbf \
    rate 100mbit \
    burst 32kbit \
    latency 400ms
```

### 完全な例（eth0の双方向制限）

```bash
#!/bin/bash
RATE="100mbit"
BURST="32kbit"
LATENCY="400ms"

# 1. IFBモジュールロード
modprobe ifb numifbs=1
ip link set ifb0 up

# 2. Egress制御（送信）
tc qdisc add dev eth0 root tbf \
    rate $RATE \
    burst $BURST \
    latency $LATENCY

# 3. Ingress制御（受信）
tc qdisc add dev eth0 ingress
tc filter add dev eth0 parent ffff: \
    protocol ip u32 match u32 0 0 \
    action mirred egress redirect dev ifb0

tc qdisc add dev ifb0 root tbf \
    rate $RATE \
    burst $BURST \
    latency $LATENCY

echo "✓ eth0: Egress=$RATE, Ingress=$RATE (via ifb0)"
```

---

## パケットの流れ

### 送信方向（Egress）- IFB不要

```
アプリケーション
    ↓ write(socket)
TCP/IPスタック
    ↓
Egress Qdisc (eth0)
    ↓ [TBF: 100Mbps制限]
ネットワークカード
    ↓
外部ネットワーク
```

### 受信方向（Ingress）- IFB使用

```
外部ネットワーク
    ↓
ネットワークカード (eth0)
    ↓
Ingress Qdisc (eth0)
    ↓ [リダイレクト]
IFB0 Egress Qdisc
    ↓ [TBF: 100Mbps制限] ← ここで制限！
カーネル受信処理
    ↓
TCP/IPスタック
    ↓ read(socket)
アプリケーション
```

### タイミング図

```
時刻  外部 → eth0 → ifb0 → カーネル
────────────────────────────────────
0ms   ■■■■ 送信開始
1ms         ■■■■ 到着
2ms              □□ リダイレクト
3ms              □□ TBF待機...
10ms                 □□ 通過（制限後）
11ms                      □□ アプリ受信
```

---

## 今回のプロジェクトでの使用例

### setup-router-single.sh の実装

```bash
#!/bin/sh
# container-init/setup-router-single.sh

echo "Setting up Single Router with TC..."

# IFBモジュールロード（11個のインターフェース用）
modprobe ifb numifbs=11

RATE="${BANDWIDTH_RATE:-100mbit}"
BURST="${BANDWIDTH_BURST:-32kbit}"
LATENCY="${BANDWIDTH_LATENCY:-400ms}"

# 各インターフェースに適用
for i in $(seq 0 10); do
    IFACE="eth$i"
    IFB_DEV="ifb$i"

    # IFB起動
    ip link set $IFB_DEV up

    # Egress制御（送信）
    tc qdisc add dev $IFACE root tbf \
        rate $RATE burst $BURST latency $LATENCY

    # Ingress制御（受信）
    tc qdisc add dev $IFACE ingress
    tc filter add dev $IFACE parent ffff: \
        protocol ip u32 match u32 0 0 \
        action mirred egress redirect dev $IFB_DEV

    tc qdisc add dev $IFB_DEV root tbf \
        rate $RATE burst $BURST latency $LATENCY

    echo "✓ $IFACE: Egress=$RATE, Ingress=$RATE (via $IFB_DEV)"
done

# 無限ループ（コンテナ維持）
tail -f /dev/null
```

### docker-compose-router.yml での設定

```yaml
router:
  image: alpine:latest
  container_name: router
  cap_add:
    - NET_ADMIN  # ← TC/IFBに必要
  sysctls:
    - net.ipv4.ip_forward=1
  environment:
    BANDWIDTH_RATE: ${BANDWIDTH_RATE:-100mbit}
  volumes:
    - ./container-init/setup-router-single.sh:/setup-router-single.sh:ro
  command: /bin/sh /setup-router-single.sh
  networks:
    - bench_net      # → eth0 + ifb0
    - ipfs_org1_net  # → eth1 + ifb1
    # ... eth10 + ifb10まで
```

### 結果

各routerインターフェース（eth0〜eth10）で：
- **Uplink（送信）**: 100Mbps制限（TBF on Egress）
- **Downlink（受信）**: 100Mbps制限（TBF on IFB Egress）
- **合計**: 200Mbps全二重通信が可能

---

## 検証方法

### 1. IFBデバイスの存在確認

```bash
docker exec router ip link show type ifb

# 期待される出力:
# 12: ifb0: <BROADCAST,NOARP,UP,LOWER_UP> mtu 1500 ...
# 13: ifb1: <BROADCAST,NOARP,UP,LOWER_UP> mtu 1500 ...
# ...
```

### 2. TC設定の確認

```bash
# Egress設定
docker exec router tc qdisc show dev eth0
# root 8001: tbf rate 100Mbit burst 32Kbit lat 400ms

# Ingress設定
docker exec router tc qdisc show dev eth0 ingress
# ingress ffff:

# IFB設定
docker exec router tc qdisc show dev ifb0
# root 8001: tbf rate 100Mbit burst 32Kbit lat 400ms
```

### 3. フィルタルールの確認

```bash
docker exec router tc filter show dev eth0 parent ffff:

# 出力:
# filter protocol ip pref 49152 u32 chain 0
# filter protocol ip pref 49152 u32 chain 0 fh 800: ht divisor 1
# filter protocol ip pref 49152 u32 chain 0 fh 800::800 order 2048 key ht 800 bkt 0
#   match 00000000/00000000 at 0
#   action order 1: mirred (Egress Redirect to device ifb0) ...
```

### 4. 帯域幅テスト（Upload - Egress制限）

```bash
# bench → org1 (eth1のEgress制限が効く)
docker exec bench ipfs-bench upload \
    --size 100MB \
    --target /dns4/ipfs-org1/tcp/4001/p2p/...

# 期待結果: 約8秒（100MB / 100Mbps = 8秒）
```

### 5. 帯域幅テスト（Download - Ingress制限）

```bash
# org1 → bench (eth0のIngress制限 = ifb0のEgress制限が効く)
docker exec bench ipfs-bench download \
    --cid QmXXX...

# 期待結果: 約8秒（ifb0で制限されている）
```

### 6. IFBカウンタの確認

```bash
# ifb0の統計情報
docker exec router ip -s link show ifb0

# 出力:
# 12: ifb0: <BROADCAST,NOARP,UP,LOWER_UP> mtu 1500 ...
#     RX: bytes  packets  errors  dropped  overrun  mcast
#     0          0        0       0        0        0      ← 常に0（受信しない）
#     TX: bytes  packets  errors  dropped  carrier  collsns
#     104857600  80000    0       1200     0        0      ← リダイレクトされたパケット
```

**重要**: IFBはRXカウンタが常に0（受信デバイスではない）、TXカウンタにリダイレクトされたパケット数が表示される。

---

## トラブルシューティング

### エラー1: `modprobe: can't change directory to '/lib/modules'`

**原因**: Dockerコンテナ内にカーネルモジュールディレクトリがない

**解決策**: ホスト側でモジュールロード、またはalpine:latestではなくLinuxカーネルヘッダ付きイメージを使用

```yaml
# docker-compose.yml
router:
  image: alpine:latest
  volumes:
    - /lib/modules:/lib/modules:ro  # ホストのモジュールをマウント
  cap_add:
    - NET_ADMIN
    - SYS_MODULE  # モジュールロードに必要
```

### エラー2: `RTNETLINK answers: Operation not permitted`

**原因**: `NET_ADMIN` capabilityがない

**解決策**:
```yaml
cap_add:
  - NET_ADMIN  # これが必須
```

### エラー3: IFBにリダイレクトされない

**デバッグ**:
```bash
# フィルタが正しく設定されているか確認
tc filter show dev eth0 parent ffff:

# ifb0のカウンタが増えているか確認
watch -n 1 'ip -s link show ifb0'
```

**原因**: フィルタルールのミス（`u32 match` が間違っている）

**解決策**:
```bash
# すべてのIPv4パケットをマッチさせる正しい書き方
tc filter add dev eth0 parent ffff: \
    protocol ip \
    u32 match u32 0 0 \
    action mirred egress redirect dev ifb0
```

### エラー4: 帯域制限が効いていない

**確認**:
```bash
# TC統計情報
tc -s qdisc show dev ifb0

# 出力:
# qdisc tbf 8001: root refcnt 2 rate 100Mbit burst 32Kb lat 400ms
#  Sent 104857600 bytes 80000 pkt (dropped 1200, overlimits 2500 requeues 0)
```

- **dropped**: バッファオーバーフローで破棄
- **overlimits**: レート制限に達した回数

→ これらが増えていれば制限が効いている

### エラー5: パフォーマンスが極端に悪い

**原因**: `burst`サイズが小さすぎる、または`latency`が大きすぎる

**調整**:
```bash
# burst を大きく、latency を小さく
tc qdisc replace dev ifb0 root tbf \
    rate 100mbit \
    burst 128kbit \  # 32kbit → 128kbit
    latency 50ms     # 400ms → 50ms
```

---

## まとめ

### IFBの重要ポイント

| 項目 | 説明 |
|------|------|
| **目的** | Ingress（受信）トラフィックに帯域制限を適用 |
| **原理** | 受信パケットを仮想デバイスの送信として扱う |
| **必要権限** | `NET_ADMIN` capability |
| **カーネルモジュール** | `ifb`（標準カーネルに含まれる） |
| **使用場面** | 双方向の帯域制限が必要な場合 |
| **代替手段** | IMQ（非標準）、送信側制御（不可能な場合あり） |

### 今回のプロジェクトでの効果

- ✅ **Egress**: 各インターフェースで100Mbps制限
- ✅ **Ingress**: IFB経由で100Mbps制限
- ✅ **全二重**: 合計200Mbps（送受信独立）
- ✅ **一元管理**: routerコンテナで11インターフェース制御
- ✅ **Docker Compose互換**: 標準機能のみ使用

### 参考リンク

- [Linux TC Documentation](https://tldp.org/HOWTO/Traffic-Control-HOWTO/)
- [IFB Kernel Documentation](https://www.kernel.org/doc/Documentation/networking/ifb.txt)
- [tc-mirred man page](https://man7.org/linux/man-pages/man8/tc-mirred.8.html)
