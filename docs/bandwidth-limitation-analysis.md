# 帯域制限の問題点と解決策

## 問題の発見

現在のDocker環境で帯域制限テストを行った結果、予期しない挙動が発見されました。

## 現実のインターネット環境 vs Docker仮想ネットワーク

### 現実のインターネット環境 (正しい挙動)

```
自宅 (10Mbps回線)
  └── ipfs-bench
       ↓ 10Mbps総量制限 (物理的な回線の上限)
  インターネット
       ↓
  ├── ipfs-org1 (10Mbps)
  ├── ipfs-org2 (10Mbps)
  └── ipfs-org3 (10Mbps)
```

**結果:** 総ダウンロード速度 = **10Mbps**

複数ノードから同時にダウンロードしても、自宅の回線が10Mbpsなら**合計10Mbps以上は出ません**。

---

### 現在のDocker環境 (問題あり)

```
Docker Network (仮想ネットワーク)
  ├── ipfs-bench (10Mbps egress制限)
  ├── ipfs-org1 (10Mbps egress制限)
  ├── ipfs-org2 (10Mbps egress制限)
  └── ipfs-org3 (10Mbps egress制限)
```

pumbaのnetem rateは**各コンテナの送信(egress)のみを制限**しています。

- ipfs-org1 → ipfs-bench: 10Mbps制限 ✅
- ipfs-org2 → ipfs-bench: 10Mbps制限 ✅
- ipfs-org3 → ipfs-bench: 10Mbps制限 ✅

**しかし、ipfs-benchの受信(ingress)は制限されていない！**

**結果:** 総ダウンロード速度 = **30Mbps以上** ❌

---

## 詳細分析

### Pumba netem rateの挙動

**Pumba netem rate**は、Linuxの`tc qdisc`を使用して帯域制限を実装しています。

#### 制限されるもの
- ✅ **Egress (送信)**: コンテナから外への送信トラフィック
- ❌ **Ingress (受信)**: コンテナへの受信トラフィックは**制限されない**

#### 現在の設定の効果

```bash
# limit-bandwidth-all.sh で全コンテナに適用
pumba netem rate --rate 10mbit <container>
```

これにより:
- ipfs-org1のegress: 10Mbps制限
- ipfs-org2のegress: 10Mbps制限
- ipfs-org3のegress: 10Mbps制限
- ipfs-benchのegress: 10Mbps制限

---

### Upload (送信) の挙動 - 正常 ✅

ipfs-benchが複数ノードにアップロードする場合:

```
ipfs-bench (egress: 10Mbps制限)
  ├─→ ipfs-org1 (10/3 ≒ 3.3Mbps)
  ├─→ ipfs-org2 (10/3 ≒ 3.3Mbps)
  └─→ ipfs-org3 (10/3 ≒ 3.3Mbps)

総送信: 10Mbps ✅
```

**pumba netem rateは送信側の総量を制限**するため、ipfs-benchが複数ノードに送信しても**合計10Mbpsに制限される**。

**Upload側は問題なし！**

---

### Download (受信) の挙動 - 問題あり ❌

ipfs-benchが複数ノードからダウンロードする場合:

```
ipfs-bench (ingress: 制限なし ❌)
  ←─ ipfs-org1 (egress: 10Mbps) → 10Mbps受信
  ←─ ipfs-org2 (egress: 10Mbps) → 10Mbps受信
  ←─ ipfs-org3 (egress: 10Mbps) → 10Mbps受信

総受信: 30Mbps ❌
```

各送信ノードのegress制限は効いているが、**ipfs-benchのingressに制限がない**ため、全ての送信が通ってしまう。

**Download側が問題！**

---

## Pumbaの制限事項

### Pumba netem rate

- ✅ Egress (送信) 制限: 可能
- ❌ Ingress (受信) 制限: **不可能**

### Pumba iptables loss

- ✅ Ingressのパケットロス: 可能
- ❌ Ingressの帯域制限: **不可能**

**結論:** Pumbaではingress帯域制限はできない

---

## 解決策

> **💡 推奨:** より現実的なアプローチとして、[Router Pod アーキテクチャ](./router-pod-architecture.md)を検討してください。各ノードに専用ルータを配置することで、現実の家庭回線環境を正確にシミュレートできます。

### 方法1: tc qdiscを直接使用

ipfs-benchコンテナ内で直接`tc qdisc`を使用してingress制限を適用する。

```bash
# ipfs-benchコンテナ内で実行
docker exec ipfs-bench tc qdisc add dev eth0 handle ffff: ingress
docker exec ipfs-bench tc filter add dev eth0 parent ffff: protocol ip prio 50 \
  u32 match ip src 0.0.0.0/0 \
  police rate 10mbit burst 10k drop flowid :1
```

**メリット:**
- 確実にingress制限が効く
- Pumbaのnetemと併用可能
- 最も直接的な解決策

**デメリット:**
- スクリプトで自動化が必要
- コンテナに`iproute2`パッケージが必要

---

### 方法2: 設計を変更する

各提供ノード(ipfs-org1/2/3)のegress制限を下げる。

```bash
# 各ノードを3Mbpsに制限
pumba netem rate --rate 3mbit ipfs-org1
pumba netem rate --rate 3mbit ipfs-org2
pumba netem rate --rate 3mbit ipfs-org3

# ipfs-benchは10Mbps
pumba netem rate --rate 10mbit ipfs-bench
```

**結果:** 3Mbps × 3 = 9Mbps (≒10Mbps)

**メリット:**
- Pumbaだけで完結
- 追加設定不要

**デメリット:**
- 各ノードの帯域が不自然に低い
- ノード数が変わると調整が必要
- 厳密な制限ではない

---

### 方法3: Wondershaper等の代替ツール

Wondershaperはingress/egressの両方を制限可能。

```bash
docker exec ipfs-bench wondershaper eth0 10000 10000
#                                      ↑upload ↑download
```

**メリット:**
- ingress/egress両方を簡単に設定
- 分かりやすいインターフェース

**デメリット:**
- 各コンテナにwondershaperのインストールが必要
- Pumbaの統一的な管理から外れる

---

## 推奨アプローチ

**方法1 (tc qdisc直接使用) + Pumba netemの併用**

1. **Pumba netem rate**: 全コンテナのegress制限 (既存)
2. **tc qdisc ingress**: ipfs-benchのingress制限 (追加)

### 実装スクリプト例

```bash
#!/bin/bash
# scripts/network-chaos/apply-realistic-bandwidth.sh

RATE="10mbit"

# 1. Pumbaで全コンテナのegressを制限
./scripts/network-chaos/limit-bandwidth-all.sh $RATE

# 2. ipfs-benchのingressを制限
docker exec ipfs-bench tc qdisc add dev eth0 handle ffff: ingress
docker exec ipfs-bench tc filter add dev eth0 parent ffff: protocol ip prio 50 \
  u32 match ip src 0.0.0.0/0 \
  police rate $RATE burst 10k drop flowid :1

echo "✅ Realistic bandwidth limits applied:"
echo "   - All containers egress: $RATE (via pumba)"
echo "   - ipfs-bench ingress: $RATE (via tc qdisc)"
```

---

## まとめ

| 方向 | 対象 | 現状 | 必要な対応 | ツール |
|------|------|------|----------|--------|
| **Upload** | ipfs-benchのegress | ✅ 制限済み (10Mbps) | なし | Pumba netem rate |
| **Download** | ipfs-benchのingress | ❌ 未制限 (30Mbps+) | 制限追加 | tc qdisc ingress |

### 現在の問題

- Download時に複数ノードから同時受信すると、合計帯域が10Mbpsを超えてしまう
- 現実のインターネット環境を正確にシミュレートできていない

### 解決後の挙動

```
ipfs-bench (ingress: 10Mbps, egress: 10Mbps)
  ↕ 合計10Mbps制限
各IPFSノード (egress: 10Mbps)
```

- Upload: 10Mbps総量制限 ✅
- Download: 10Mbps総量制限 ✅
- 現実のインターネット環境を正確にシミュレート ✅

---

## 参考図

詳細な図は `network-bandwidth-diagram.drawio` を参照してください。

https://app.diagrams.net/ で開くことができます。

---

## 次のステップ

1. [ ] tc qdiscによるingress制限スクリプトを作成
2. [ ] 統合スクリプト`apply-realistic-bandwidth.sh`を実装
3. [ ] テストを実行して帯域制限が正しく動作することを確認
4. [ ] Makefileにターゲットを追加

---

## 関連ファイル

- `scripts/network-chaos/limit-bandwidth-all.sh` - Pumba netem rate適用スクリプト
- `network-bandwidth-diagram.drawio` - 視覚的な問題説明図
- `/tmp/make-bandwidth-test.log` - テスト結果ログ
