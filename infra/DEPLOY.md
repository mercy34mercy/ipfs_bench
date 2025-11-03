# デプロイ手順（research-383706）

プリエンプティブVMでIPFSベンチマーク環境を構築します。

## ✅ 準備完了

以下の設定でデプロイします：

```yaml
プロジェクト: research-383706
リージョン: asia-northeast1（東京）
ノード数: 4台
マシンタイプ: e2-standard-2（2 vCPU, 8 GB）
VM種別: プリエンプティブ（80%割引）
静的IP: なし（動的IP）

想定コスト（8時間）: 約 ¥1,020
```

## 🚀 デプロイ手順

### ステップ 1: 認証

```bash
# Google アカウントで認証（etukobamasatyan@gmail.com）
gcloud auth login

# Terraform用の認証
gcloud auth application-default login

# プロジェクトを設定
gcloud config set project research-383706
```

### ステップ 2: Compute Engine API の有効化

```bash
# API を有効化
gcloud services enable compute.googleapis.com
```

または GCP Console から:
https://console.cloud.google.com/apis/library/compute.googleapis.com?project=research-383706

### ステップ 3: Terraform 初期化

```bash
# infra ディレクトリに移動
cd infra

# Terraform を初期化
terraform init
```

### ステップ 4: プランを確認

```bash
# 何が作成されるか確認
terraform plan
```

**作成されるリソース:**
- Compute Engine インスタンス × 4台
- ファイアウォールルール × 1個
- 合計: 5リソース

### ステップ 5: デプロイ実行

```bash
# リソースを作成
terraform apply

# "yes" と入力して確認
```

**所要時間:** 約 2-3 分

### ステップ 6: 接続情報の確認

```bash
# SSH コマンドを表示
terraform output ssh_commands

# または詳細情報を表示
terraform output quick_start_instructions
```

## 📊 デプロイ後の確認

### インスタンスが起動しているか確認

```bash
gcloud compute instances list --project=research-383706
```

**期待される出力:**
```
NAME              ZONE               MACHINE_TYPE   PREEMPTIBLE  STATUS
ipfs-bench-node-1 asia-northeast1-a  e2-standard-2  true         RUNNING
ipfs-bench-node-2 asia-northeast1-a  e2-standard-2  true         RUNNING
ipfs-bench-node-3 asia-northeast1-a  e2-standard-2  true         RUNNING
ipfs-bench-node-4 asia-northeast1-a  e2-standard-2  true         RUNNING
```

### ファイアウォールルールを確認

```bash
gcloud compute firewall-rules describe ipfs-bench-allow-ipfs --project=research-383706
```

### 外部IPアドレスを確認

```bash
terraform output external_ips
```

## 🔌 インスタンスに接続

### SSH で接続（推奨）

```bash
# ノード1に接続
gcloud compute ssh ipfs-bench-node-1 --zone=asia-northeast1-a --project=research-383706

# ノード2に接続
gcloud compute ssh ipfs-bench-node-2 --zone=asia-northeast1-a --project=research-383706

# 以下同様...
```

### 初回接続時

Dockerが自動インストールされているか確認:

```bash
# Docker バージョン確認
docker --version

# Docker Compose バージョン確認
docker-compose --version

# tc コマンド確認
tc -version
```

すべて正常にインストールされているはずです。

## 🧪 ベンチマーク実行

### 1. リポジトリをクローン（自動クローンされていない場合）

```bash
git clone https://github.com/your-username/ipfs_bench.git
cd ipfs_bench
```

**または** repo_url を設定していた場合は既にクローンされています:

```bash
cd ~/ipfs_bench
```

### 2. Docker Compose で IPFS ノードを起動

```bash
# IPFS ノードを起動
docker-compose up -d

# 起動確認
docker ps
```

### 3. ネットワーク制限を適用（オプション）

```bash
# 10 Mbps に制限
export BANDWIDTH_RATE="10mbit"
export NETWORK_DELAY="50ms"
export PACKET_LOSS="1"

sudo ./container-init/setup-router-tc.sh
```

### 4. ベンチマークを実行

```bash
# 既存のベンチマークスクリプトを実行
./run_bench_10nodes.sh

# または main.go を使用
go run main.go
```

### 5. 結果を確認

```bash
# 結果ファイルを確認
ls -lh test-results/

# CSV ファイルを表示
cat test-results/bench_*.csv
```

### 6. 結果をローカルにダウンロード

```bash
# 別のターミナルで実行（ローカル）
gcloud compute scp ipfs-bench-node-1:~/ipfs_bench/test-results/ ./results/ \
  --zone=asia-northeast1-a \
  --project=research-383706 \
  --recurse
```

## 📈 結果の分析（ローカル）

```bash
# ローカルで分析スクリプトを実行
cd ipfs_bench
python3 analyze_results.py results/bench_*.csv

# 可視化
python3 visualize_results.py results/bench_*.csv
```

## 🧹 クリーンアップ

### すべてのリソースを削除

```bash
# infra ディレクトリで実行
cd infra

terraform destroy

# "yes" と入力して確認
```

**重要:** 使い終わったら必ず `terraform destroy` を実行してください！

### 個別のインスタンスを停止（一時的）

```bash
# インスタンスを停止（ディスク代のみ課金）
gcloud compute instances stop ipfs-bench-node-1 --zone=asia-northeast1-a --project=research-383706

# 再開
gcloud compute instances start ipfs-bench-node-1 --zone=asia-northeast1-a --project=research-383706
```

## ⚠️ プリエンプティブVMの注意事項

### 1. 24時間以内に停止される

- 最長24時間で必ず停止
- 8時間のベンチマークなら問題なし

### 2. 停止される前にバックアップ

```bash
# 定期的に結果をダウンロード
while true; do
  gcloud compute scp ipfs-bench-node-1:~/ipfs_bench/test-results/ ./backup/ \
    --zone=asia-northeast1-a \
    --project=research-383706 \
    --recurse
  sleep 3600  # 1時間ごと
done
```

### 3. 停止されたら再起動

```bash
# インスタンスを再起動
gcloud compute instances start ipfs-bench-node-1 --zone=asia-northeast1-a --project=research-383706
```

## 💰 コスト確認

### GCP Console で確認

1. **請求情報:**
   https://console.cloud.google.com/billing?project=research-383706

2. **プロジェクトのコスト:**
   https://console.cloud.google.com/billing/projects/research-383706

### 想定コスト（8時間）

```
インスタンス（e2-standard-2 プリエンプティブ × 4台）: $0.64
ディスク（30GB × 4台）:                                $0.16
ネットワーク（50GB 送信）:                            $6.00
──────────────────────────────────────────────────────
合計:                                                  $6.80
円換算（¥150/$）:                                      ¥1,020
```

## 🔧 トラブルシューティング

### エラー: API has not been used

```bash
gcloud services enable compute.googleapis.com --project=research-383706
```

### エラー: insufficient authentication scopes

```bash
gcloud auth application-default login
```

### SSH 接続できない

```bash
# ファイアウォールルールを確認
gcloud compute firewall-rules list --project=research-383706

# インスタンスの状態を確認
gcloud compute instances list --project=research-383706

# シリアルポート出力を確認（起動ログ）
gcloud compute instances get-serial-port-output ipfs-bench-node-1 \
  --zone=asia-northeast1-a \
  --project=research-383706
```

### インスタンスが停止された

```bash
# 状態を確認
gcloud compute instances list --project=research-383706

# 停止されていたら再起動
gcloud compute instances start ipfs-bench-node-1 --zone=asia-northeast1-a --project=research-383706
```

## 📚 参考資料

- [Terraform 設定: `infra/main.tf`](./main.tf)
- [変数定義: `infra/variables.tf`](./variables.tf)
- [詳細ドキュメント: `infra/README.md`](./README.md)
- [クイックスタート: `infra/QUICKSTART.md`](./QUICKSTART.md)
- [プリエンプティブVM解説: `docs/preemptible_vs_ondemand.md`](../docs/preemptible_vs_ondemand.md)
- [コスト詳細: `docs/gcp_cost_breakdown.md`](../docs/gcp_cost_breakdown.md)

## ✅ チェックリスト

デプロイ前:
- [ ] gcloud 認証完了
- [ ] Compute Engine API 有効化
- [ ] terraform.tfvars 確認（project_id = research-383706）

デプロイ後:
- [ ] インスタンスが RUNNING 状態
- [ ] SSH 接続確認
- [ ] Docker インストール確認
- [ ] ベンチマーク実行
- [ ] 結果のダウンロード

クリーンアップ:
- [ ] terraform destroy 実行
- [ ] インスタンス削除確認
- [ ] 課金停止確認

## 🎉 準備完了！

設定は完了しています。あとは以下のコマンドを実行するだけです：

```bash
cd infra
terraform init
terraform apply
```

頑張ってください！
