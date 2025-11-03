# Docker Compose ネットワークレイヤー解説

## 概要

Docker Composeで構築されたIPFSベンチマークシステムのネットワークアーキテクチャを、OSIモデルの各レイヤーで詳細に解説します。

## OSIモデルとの対応

### Layer 7: アプリケーション層

**役割**: 実際のアプリケーションプロトコル

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  ipfs-bench     │     │  ipfs-org1      │     │  ipfs-org2      │
│                 │     │                 │     │                 │
│  Go Application │     │  IPFS Kubo      │     │  IPFS Kubo      │
│  HTTP Client    │────▶│  HTTP API       │◀───▶│  Bitswap        │
└─────────────────┘     └─────────────────┘     └─────────────────┘
```

**具体的な処理**:
- `ipfs-bench`: HTTP APIリクエスト送信
  ```bash
  curl http://ipfs-org2:5001/api/v0/cat?arg=QmXxx...
  ```
- `ipfs-org1/org2`: IPFSプロトコル（Bitswap, DHT, etc.）
- HTTP/1.1プロトコルによる通信

**該当コンポーネント**:
- IPFS Kubo daemon
- Go HTTP client
- Bitswapプロトコル実装

---

### Layer 4: トランスポート層

**役割**: エンドツーエンドの信頼性保証、ポート番号管理

```
TCP Socket :5001  ←→  TCP Socket :5001
TCP Socket :4001  ←→  TCP Socket :4001
```

**具体的な処理**:
- TCPコネクション確立（3-way handshake）
- データの順序保証
- 再送制御
- フロー制御

**使用ポート**:
- `:5001` - IPFS HTTP API
- `:4001` - IPFS Swarm (P2P通信)
- `:8080` - IPFS Gateway

**確認コマンド**:
```bash
# コンテナ内でポート使用状況を確認
docker exec ipfs-org1 netstat -tlnp
```

---

### Layer 3: ネットワーク層

**役割**: IPアドレスによるルーティング、パケット転送

#### 各コンテナのIP設定

```
ipfs-bench:  172.31.100.10/24  → Gateway: 172.31.100.1
ipfs-org1:   172.31.1.10/24    → Gateway: 172.31.1.1
ipfs-org2:   172.31.2.10/24    → Gateway: 172.31.2.1
ipfs-org3:   172.31.3.10/24    → Gateway: 172.31.3.1
...
ipfs-org10:  172.31.10.10/24   → Gateway: 172.31.10.1
```

#### Routerコンテナのインターフェース

Routerは11個のネットワークインターフェースを持つ：

```
eth0: 172.31.100.1/24  (bench_net)
eth1: 172.31.1.1/24    (ipfs_org1_net)
eth2: 172.31.2.1/24    (ipfs_org2_net)
eth3: 172.31.3.1/24    (ipfs_org3_net)
...
eth10: 172.31.10.1/24  (ipfs_org10_net)
```

#### IP Forwarding（ルーティング）

Routerコンテナで有効化：

```bash
# sysctl設定
net.ipv4.ip_forward=1
```

**ルーティングテーブル例**:
```
Destination     Gateway         Genmask         Iface
172.31.1.0      0.0.0.0         255.255.255.0   eth1
172.31.2.0      0.0.0.0         255.255.255.0   eth2
172.31.100.0    0.0.0.0         255.255.255.0   eth0
```

**パケットの流れ**:
```
ipfs-bench (172.31.100.10) → ipfs-org1 (172.31.1.10)

1. ipfs-bench: 送信先172.31.1.10, GW 172.31.100.1へ送信
2. router eth0: パケット受信
3. router: ルーティングテーブル参照 → eth1へ転送
4. router eth1: 172.31.1.10へ送信
5. ipfs-org1: パケット受信
```

---

### Layer 2: データリンク層

**役割**: 同一ネットワーク内の通信、MACアドレス管理

#### Docker Bridgeネットワーク

各ネットワークは独立したLinux Bridgeデバイスとして実装：

```bash
# Bridgeデバイス一覧
$ docker network ls
NETWORK ID     NAME              DRIVER    SCOPE
abc123def456   bench_net         bridge    local
def789ghi012   ipfs_org1_net     bridge    local
ghi345jkl678   ipfs_org2_net     bridge    local
...
```

実際のLinuxデバイス:
```bash
# Host上でのBridge確認
$ ip link show type bridge
br-abc123def456: <BROADCAST,MULTICAST,UP>  # bench_net
br-def789ghi012: <BROADCAST,MULTICAST,UP>  # ipfs_org1_net
br-ghi345jkl678: <BROADCAST,MULTICAST,UP>  # ipfs_org2_net
```

#### Virtual Ethernet (veth)

各コンテナとBridgeはvethペアで接続：

```
Container Namespace          Host Namespace
┌─────────────────┐         ┌─────────────────┐
│  eth0 (veth)    │◀───────▶│  vethXXX        │
│  172.31.1.10    │         │  (bridge port)  │
└─────────────────┘         └─────────────────┘
                                    │
                            ┌───────▼──────────┐
                            │  br-xxx (bridge) │
                            └──────────────────┘
```

**MACアドレス**:
- DockerはIPアドレスからMAC生成: `02:42:ac:1f:01:0a`
  - `02:42` - Docker固定プレフィックス
  - `ac:1f:01:0a` - 172.31.1.10のHEX表現

**確認コマンド**:
```bash
# コンテナ内のインターフェース
docker exec ipfs-org1 ip link show eth0
# 出力例:
# eth0@if123: <BROADCAST,MULTICAST,UP> mtu 1500
#     link/ether 02:42:ac:1f:01:0a

# Host側のveth
ip link show | grep veth
```

#### Linux Bridge動作

Bridgeは**Layer 2スイッチ**として動作：

1. **MACアドレステーブル**を保持
2. **ブロードキャスト**をすべてのポートに転送
3. **ユニキャスト**は該当ポートのみに転送

```bash
# Bridge MACテーブル確認
$ bridge fdb show br br-abc123def456
02:42:ac:1f:64:0a dev veth123 master br-abc123def456
02:42:ac:1f:01:01 dev veth456 master br-abc123def456
```

---

### Layer 1: 物理層

**役割**: ビット列の物理的な送受信

Docker環境では**仮想化**されている：

```
┌─────────────────────────────────────────────┐
│  Host Physical NIC (Ethernet / Wi-Fi)      │
│  - 電気信号 / 光信号 / 電波                 │
│  - MAC層PHY（物理層）                       │
└─────────────────────────────────────────────┘
              ▲
              │ (仮想化)
              │
┌─────────────┴───────────────────────────────┐
│  Docker Virtual Network Stack              │
│  - Software-based packet forwarding        │
│  - Kernel network namespace                │
└────────────────────────────────────────────┘
```

**実際の物理層**:
- bench_netのみがHost NICに接続可能
- `internal: true`ネットワークは物理層に到達しない

---

## `internal: true`の意味

### 通常のDocker Network

```
Container → Docker Bridge → Host iptables → Physical NIC → Internet
                                ↑
                          (NAT/Forwarding)
```

### `internal: true` Network

```
Container → Docker Bridge → ✗ (Blocked)
                      ↑
               No external access
```

**設定箇所**（docker-compose-router.yml）:
```yaml
networks:
  ipfs_org1_net:
    driver: bridge
    internal: true  # ← これ！
    ipam:
      config:
        - subnet: 172.31.1.0/24
```

**効果**:
1. Host側のiptables NAT ルールが作成されない
2. 外部ネットワークへのルーティング不可
3. Dockerの自動ルーティングが無効化

**確認コマンド**:
```bash
# internal networkから外部疎通テスト（失敗する）
docker exec ipfs-org1 ping 8.8.8.8
# Network is unreachable

# bench_netから外部疎通（成功）
docker exec ipfs-bench ping 8.8.8.8
# 64 bytes from 8.8.8.8: icmp_seq=1 ttl=117 time=10 ms
```

---

## Traffic Control (TC)の動作レイヤー

TCはLayer 2/3の境界で動作：

```
Layer 3 (IP)
    │
    ▼
┌─────────────────────────────────┐
│  TC Queuing Discipline (qdisc)  │  ← ここでパケット制御
│  - tbf (Token Bucket Filter)    │
│  - netem (Network Emulator)      │
└─────────────────────────────────┘
    │
    ▼
Layer 2 (Ethernet Frame)
```

### Egress（送信）制御

```bash
tc qdisc add dev eth1 root tbf \
  rate 100mbit \
  burst 10mbit \
  latency 1ms
```

- **rate**: 平均帯域幅
- **burst**: 瞬間的に許可する最大量
- **latency**: パケットがキューに留まれる最大時間

### Ingress（受信）制御

IFB（Intermediate Functional Block）を使用：

```bash
# IFBデバイス作成
ip link add ifb0 type ifb
ip link set ifb0 up

# 受信パケットをIFBにリダイレクト
tc qdisc add dev eth1 handle ffff: ingress
tc filter add dev eth1 parent ffff: protocol ip \
  matchall action mirred egress redirect dev ifb0

# IFBで帯域幅制限
tc qdisc add dev ifb0 root tbf \
  rate 100mbit \
  burst 10mbit \
  latency 1ms
```

**なぜIFBが必要？**
- Linuxカーネルは送信（egress）のqueuing disciplineは充実
- 受信（ingress）は直接制御が困難
- IFBにリダイレクトして「送信」として処理

---

## パケットの完全な経路

### Upload: ipfs-bench → ipfs-org1

```
【Layer 7】
ipfs-bench: HTTP POST /api/v0/add
  ↓
【Layer 4】
TCP Socket :5001
  ↓
【Layer 3】
IP: 172.31.100.10 → 172.31.1.10
Route: via 172.31.100.1 (default gateway)
  ↓
【Layer 2】
ARP: 172.31.100.1のMAC解決
Ethernet Frame: src=02:42:ac:1f:64:0a, dst=02:42:ac:1f:64:01
  ↓
veth pair → bench_net bridge
  ↓
bench_net bridge → router eth0
  ↓
【Router: Layer 3】
router: IP Forward enabled
Routing Table: 172.31.1.0/24 → eth1
  ↓
【Router: TC Layer 2/3】
TC (eth1): rate 100mbit, burst 10mbit
  ↓
【Layer 2】
router eth1 → ipfs_org1_net bridge
  ↓
ipfs_org1_net bridge → ipfs-org1 veth
  ↓
【Layer 3】
ipfs-org1: IP 172.31.1.10で受信
  ↓
【Layer 4】
TCP Socket :5001で受信
  ↓
【Layer 7】
IPFS Kubo: ファイル受信・保存
```

### Download: ipfs-bench → ipfs-org2 → ipfs-org1 → ipfs-org2 → ipfs-bench

#### ステップ1: ipfs-bench → ipfs-org2 (HTTP Request)

```
L7: GET /api/v0/cat?arg=QmXxx
L4: TCP :5001
L3: 172.31.100.10 → 172.31.2.10
L2: bench_net → router eth0 → router eth2 → ipfs_org2_net
TC: eth2で帯域幅制限（100mbit）
```

#### ステップ2: ipfs-org2 → ipfs-org1 (Bitswap Request)

```
L7: Bitswap "want block QmXxx"
L4: TCP :4001
L3: 172.31.2.10 → 172.31.1.10
L2: ipfs_org2_net → router eth2 → router eth1 → ipfs_org1_net
TC: eth2 (egress) & eth1 (ingress) で帯域幅制限
```

#### ステップ3: ipfs-org1 → ipfs-org2 (Bitswap Response - ストリーミング)

```
L7: Bitswap "block QmXxx (256KB chunk)"
L4: TCP :4001
L3: 172.31.1.10 → 172.31.2.10
L2: ipfs_org1_net → router eth1 → router eth2 → ipfs_org2_net
TC: eth1 (egress) & eth2 (ingress) で帯域幅制限

※ パイプライン処理:
  org2はブロック受信と同時にbenchへの転送を開始
```

#### ステップ4: ipfs-org2 → ipfs-bench (HTTP Response - ストリーミング)

```
L7: HTTP chunked response (256KB chunk)
L4: TCP :5001
L3: 172.31.2.10 → 172.31.100.10
L2: ipfs_org2_net → router eth2 → router eth0 → bench_net
TC: eth2 (egress) で帯域幅制限

※ ステップ3と並行実行（パイプライン処理）
```

---

## 全二重（Full-Duplex）の効果

### eth2での同時通信

```
Time: 0.0s
  org1 → org2: Block 0送信開始 ▶▶▶ eth2 ingress (100Mbps)
  org2 → bench: Block 0転送開始 ◀◀◀ eth2 egress (100Mbps)
                                    ↑
                        同時実行可能！（全二重）

Time: 0.1s
  org1 → org2: Block 1送信      ▶▶▶ eth2 ingress
  org2 → bench: Block 1転送     ◀◀◀ eth2 egress
```

**物理的な実装**（veth pair）:
```
┌──────────────────────────────────────┐
│  veth pair (Software implementation) │
│                                      │
│  TX queue (送信)  ◀──────┐          │
│  RX queue (受信)  ────────▶          │
│                                      │
│  → 独立したキュー、同時処理可能      │
└──────────────────────────────────────┘
```

**TC制限の適用**:
- Egress (送信): 100Mbps制限
- Ingress (受信): IFB経由で100Mbps制限
- 合計理論容量: 200Mbps

**しかし実測は1.18x（理論1.0xに対して）**:
- CPU処理オーバーヘッド
- TC queuing処理
- IFBリダイレクト処理
- コンテキストスイッチ

---

## 確認コマンド集

### ネットワーク構成確認

```bash
# Docker networks
docker network ls
docker network inspect bench_net

# コンテナのIP
docker exec ipfs-org1 ip addr show eth0

# Routerのインターフェース
docker exec router ip addr show

# Routingテーブル
docker exec router ip route show

# ARPテーブル
docker exec ipfs-bench ip neigh show
```

### TC設定確認

```bash
# Egress qdisc確認
docker exec router tc qdisc show dev eth1

# Ingress filter確認
docker exec router tc filter show dev eth1 parent ffff:

# IFBデバイス確認
docker exec router ip link show type ifb

# 詳細統計
docker exec router tc -s qdisc show dev eth1
```

### 疎通確認

```bash
# Ping (ICMP)
docker exec ipfs-bench ping -c 3 172.31.1.10

# TCP接続確認
docker exec ipfs-bench nc -zv 172.31.1.10 5001

# HTTP API確認
docker exec ipfs-bench wget -O- http://172.31.1.10:5001/api/v0/version
```

### パケットキャプチャ

```bash
# Router eth1でのキャプチャ
docker exec router tcpdump -i eth1 -n -c 100

# 特定IP間の通信
docker exec router tcpdump -i eth1 host 172.31.1.10 and host 172.31.2.10

# HTTPトラフィックのみ
docker exec router tcpdump -i eth1 'tcp port 5001' -A
```

---

## まとめ

### レイヤー別の主要コンポーネント

| Layer | OSI名 | Docker実装 | 制御場所 |
|-------|-------|-----------|---------|
| 7 | Application | IPFS Kubo, Go HTTP | Container |
| 4 | Transport | TCP/UDP | Container (Linux kernel) |
| 3 | Network | IP, Routing | Router container, iptables |
| 2 | Data Link | Bridge, veth | Host kernel, **TC** |
| 1 | Physical | (Virtual) | Host NIC |

### 重要なポイント

1. **Docker Bridge = Layer 2スイッチ**
   - Linux Bridgeデバイス（br-xxx）
   - MACアドレステーブルで転送

2. **Router Container = Layer 3ルーター**
   - IP Forwarding有効化
   - 複数サブネット間の転送

3. **TC = Layer 2/3境界**
   - パケットqueuing制御
   - 帯域幅・遅延・パケットロス制御

4. **veth = 仮想Ethernetペア**
   - コンテナとBridgeを接続
   - 全二重通信可能

5. **internal:true = 外部隔離**
   - Host NICへのアクセス不可
   - Docker自動ルーティング無効

この理解により、IPFSベンチマークシステムの正確なネットワーク動作とパフォーマンス特性を把握できます。

---

**関連ドキュメント**:
- [IPFS Performance Analysis](./ipfs_performance_analysis.md)
- [Network Layers Diagram](./docker_network_layers.drawio)

**作成日**: 2025-10-27
