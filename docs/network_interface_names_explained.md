# ネットワークインターフェース名の説明

## ens4 や eth0 は何？

**ネットワークインターフェース名** = ネットワークカードの識別名

コンピュータのネットワークカード（仮想含む）にアクセスするための名前です。

## 例え話

```
コンピュータ = 建物
ネットワークインターフェース = 出入口（ドア）
インターフェース名 = ドアの名前（「正面玄関」「裏口」など）
```

建物に複数の出入口があるように、コンピュータにも複数のネットワークインターフェースがあります。

## よくある名前

### 1. eth0, eth1, eth2...

**意味:** Ethernet 0, 1, 2...

**使われる場所:**
- 古い Linux システム
- Docker コンテナ
- AWS EC2（一部）
- 物理サーバー

**例:**
```bash
$ ip link show
1: lo: <LOOPBACK,UP,LOWER_UP> ...
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> ...  # ← これ
3: eth1: <BROADCAST,MULTICAST,UP,LOWER_UP> ...
```

### 2. ens3, ens4, ens5...

**意味:** Ethernet Network System 3, 4, 5...

**使われる場所:**
- 最近の Linux システム（systemd の Predictable Network Interface Names）
- GCP Compute Engine
- 一部の AWS EC2
- Ubuntu 16.04 以降

**例:**
```bash
$ ip link show
1: lo: <LOOPBACK,UP,LOWER_UP> ...
2: ens4: <BROADCAST,MULTICAST,UP,LOWER_UP> ...  # ← これ
```

### 3. enp0s3, enp0s8...

**意味:** Ethernet Network PCI bus 0 slot 3, slot 8...

**使われる場所:**
- VirtualBox
- 物理サーバー（PCI スロットに基づく命名）

**例:**
```bash
$ ip link show
1: lo: <LOOPBACK,UP,LOWER_UP> ...
2: enp0s3: <BROADCAST,MULTICAST,UP,LOWER_UP> ...  # ← これ
```

### 4. lo (loopback)

**意味:** Local Loopback

**用途:**
- 自分自身との通信
- `127.0.0.1` (localhost) に対応
- どのシステムにも必ずある

**例:**
```bash
$ ping 127.0.0.1
# lo インターフェースを使用
```

### 5. docker0, br-xxxxx

**意味:** Docker Bridge

**使われる場所:**
- Docker がインストールされたシステム
- Docker コンテナ間の通信

**例:**
```bash
$ ip link show
1: lo: <LOOPBACK,UP,LOWER_UP> ...
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> ...
3: docker0: <BROADCAST,MULTICAST,UP,LOWER_UP> ...  # ← Docker ブリッジ
4: br-a1b2c3d4: <BROADCAST,MULTICAST,UP,LOWER_UP> ...  # ← カスタムネットワーク
```

### 6. veth-xxxxx

**意味:** Virtual Ethernet

**使われる場所:**
- Docker コンテナ
- Kubernetes Pod
- 仮想マシン間接続

**例:**
```bash
$ ip link show
...
8: vethab12cd3@if7: <BROADCAST,MULTICAST,UP,LOWER_UP> ...  # ← コンテナ用
```

## クラウドプラットフォームごとの典型的な名前

### AWS EC2

**Amazon Linux 2 / RHEL:**
```
eth0  # プライマリインターフェース
eth1  # セカンダリインターフェース（追加した場合）
```

**Ubuntu 18.04 以降:**
```
ens5   # プライマリインターフェース
ens6   # セカンダリインターフェース
```

**確認方法:**
```bash
$ ip link show
$ ip addr show
```

### GCP Compute Engine

**ほとんどのイメージ:**
```
ens4   # プライマリインターフェース
ens5   # セカンダリインターフェース（追加した場合）
```

**古いイメージ:**
```
eth0
eth1
```

**確認方法:**
```bash
$ ip link show
$ ip addr show
```

### Azure

**最近の Ubuntu/RHEL:**
```
eth0   # プライマリ
```

### Docker コンテナ内

**デフォルト:**
```
lo     # ループバック
eth0   # コンテナのメインインターフェース
```

## なぜ名前が変わったのか？（eth0 → ens4）

### 古い方式（eth0, eth1...）の問題

**問題:** ブート時に検出順序が変わると名前が変わる

```
起動1回目:
- NIC A → eth0
- NIC B → eth1

起動2回目:（検出順序が逆になった！）
- NIC B → eth0  # ← あれ？昨日は eth1 だったのに
- NIC A → eth1
```

**結果:**
- ネットワーク設定が壊れる
- スクリプトが動かなくなる
- 本番障害の原因に

### 新しい方式（Predictable Network Interface Names）

**systemd v197 以降（2013年〜）**

**命名規則:**
1. ファームウェア/BIOS 情報を使用
2. PCI スロット番号を使用
3. MACアドレスを使用

**メリット:**
- 常に同じ名前
- 再起動しても変わらない
- ハードウェアの位置に基づく

**命名パターン:**
```
en    = Ethernet
wl    = Wireless LAN
ww    = Wireless WAN (WWAN)

eno1  = onboard device index 1
ens1  = hotplug slot 1
enp2s0 = PCI bus 2 slot 0
enx78e7d1ea46da = MAC address
```

## インターフェース名の確認方法

### 方法1: ip link show

```bash
$ ip link show

1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN mode DEFAULT group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
2: ens4: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1460 qdisc mq state UP mode DEFAULT group default qlen 1000
    link/ether 42:01:0a:80:00:02 brd ff:ff:ff:ff:ff:ff
```

**読み方:**
- `1:` `2:` = インターフェース番号
- `lo`, `ens4` = インターフェース名 ← **これ！**
- `<UP,LOWER_UP>` = 状態（UP = 使用可能）

### 方法2: ip addr show

```bash
$ ip addr show

1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever

2: ens4: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1460 qdisc mq state UP group default qlen 1000
    link/ether 42:01:0a:80:00:02 brd ff:ff:ff:ff:ff:ff
    inet 10.128.0.2/32 scope global dynamic ens4
       valid_lft 3455sec preferred_lft 3455sec
```

**追加情報:**
- `inet 10.128.0.2/32` = IP アドレス
- `ether 42:01:0a:80:00:02` = MAC アドレス

### 方法3: ifconfig（古い方法）

```bash
$ ifconfig

ens4: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu 1460
        inet 10.128.0.2  netmask 255.255.255.255  broadcast 0.0.0.0
        ether 42:01:0a:80:00:02  txqueuelen 1000  (Ethernet)
```

**注意:** `ifconfig` は非推奨。`ip` コマンドを使うべき。

### 方法4: ls /sys/class/net/

```bash
$ ls /sys/class/net/
docker0  ens4  lo  veth1a2b3c
```

## tc コマンドでの使用

### インターフェース名を指定

```bash
# eth0 の場合
tc qdisc add dev eth0 root tbf rate 10mbit burst 32kbit latency 400ms

# ens4 の場合
tc qdisc add dev ens4 root tbf rate 10mbit burst 32kbit latency 400ms
```

**`dev` パラメータ:** device = インターフェース名を指定

## スクリプトで自動検出する方法

### パターン1: デフォルトルートのインターフェース

```bash
#!/bin/bash

# デフォルトルートを使用しているインターフェースを取得
INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)

echo "Detected interface: $INTERFACE"

# tc を適用
tc qdisc add dev $INTERFACE root tbf rate 10mbit burst 32kbit latency 400ms
```

**出力例:**
```
Detected interface: ens4
```

### パターン2: すべての物理インターフェース

```bash
#!/bin/bash

# lo (loopback) と docker* を除外
INTERFACES=$(ls /sys/class/net/ | grep -v "^lo$" | grep -v "^docker" | grep -v "^br-" | grep -v "^veth")

for IFACE in $INTERFACES; do
    echo "Applying tc to $IFACE"
    tc qdisc add dev $IFACE root tbf rate 10mbit burst 32kbit latency 400ms
done
```

### パターン3: 環境変数で指定（フォールバック付き）

```bash
#!/bin/bash

# 環境変数があればそれを使用、なければ自動検出
INTERFACE=${INTERFACE:-$(ip route | grep default | awk '{print $5}' | head -n1)}

echo "Using interface: $INTERFACE"

tc qdisc add dev $INTERFACE root tbf rate 10mbit burst 32kbit latency 400ms
```

**使い方:**
```bash
# 自動検出
./script.sh

# 手動指定
INTERFACE=eth0 ./script.sh
```

## 既存プロジェクトでの対応

### setup-router-tc.sh の確認

プロジェクトのスクリプトを見てみましょう:

```bash
# container-init/setup-router-tc.sh の該当部分

# デフォルト: eth1（ルーターの外部インターフェース）
EXT_INTERFACE=${EXT_INTERFACE:-eth1}

# tc を適用
tc qdisc add dev $EXT_INTERFACE root tbf rate $BANDWIDTH_RATE ...
```

**対応方法:**

1. **環境変数で指定:**
```bash
export EXT_INTERFACE=ens4
./container-init/setup-router-tc.sh
```

2. **スクリプトを修正（自動検出）:**
```bash
# 自動検出を追加
if [ -z "$EXT_INTERFACE" ]; then
    # デフォルトルートのインターフェースを使用
    EXT_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
    echo "Auto-detected interface: $EXT_INTERFACE"
fi
```

## Docker コンテナ内でのインターフェース名

### デフォルト

Docker コンテナ内は**常に `eth0`**（標準的な場合）

```bash
$ docker exec -it my-container ip link show
1: lo: <LOOPBACK,UP,LOWER_UP> ...
2: eth0@if10: <BROADCAST,MULTICAST,UP,LOWER_UP> ...  # ← 常に eth0
```

**理由:**
- コンテナは独自のネットワーク名前空間を持つ
- ホストの名前（ens4 など）とは無関係
- 常に eth0 から始まる

### したがって

**既存の Docker ベースのスクリプトは修正不要！**

```bash
# コンテナ内で実行するスクリプト
tc qdisc add dev eth0 root tbf rate 10mbit ...  # ← OK！
```

## まとめ

### インターフェース名とは

コンピュータのネットワークカード（仮想含む）の識別名

### よくある名前

| 名前 | 使われる場所 |
|------|-------------|
| `eth0`, `eth1` | 古い Linux、Docker コンテナ内、AWS（一部） |
| `ens3`, `ens4` | 最近の Linux、GCP、AWS（Ubuntu） |
| `enp0s3` | VirtualBox、物理サーバー |
| `lo` | ループバック（どこでも） |
| `docker0` | Docker ブリッジ |

### 確認方法

```bash
ip link show
ip addr show
```

### tc での使い方

```bash
# 名前を指定
tc qdisc add dev ens4 root tbf rate 10mbit ...

# 自動検出
IFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
tc qdisc add dev $IFACE root tbf rate 10mbit ...
```

### Docker コンテナ内

**常に `eth0`** なので、既存スクリプトは修正不要！

### クラウド移行時の対応

1. **確認する:**
```bash
ip link show
```

2. **環境変数で指定:**
```bash
export INTERFACE=ens4
./your-script.sh
```

3. **または自動検出を実装**（推奨）

**既存プロジェクトの Docker ベースなら、そのまま動きます！**
