# IPFS Benchmark Infrastructure - Terraform

このディレクトリには、GCP Compute Engine 上に IPFS ベンチマーク環境を構築するための Terraform 設定が含まれています。

## 前提条件

1. **Google Cloud SDK (gcloud) のインストール**

   ```bash
   # macOS
   brew install --cask google-cloud-sdk

   # または公式サイトからダウンロード
   # https://cloud.google.com/sdk/docs/install
   ```

2. **Terraform のインストール**

   ```bash
   # macOS
   brew install terraform

   # バージョン確認
   terraform version
   ```

3. **GCP プロジェクトの準備**
   - GCP プロジェクトを作成済み
   - 課金が有効化されている
   - Compute Engine API が有効

## セットアップ手順

### ステップ 1: gcloud の認証

```bash
# Google アカウントで認証
gcloud auth login

# アプリケーションのデフォルト認証情報を設定（Terraform 用）
gcloud auth application-default login

# プロジェクトを設定
gcloud config set project YOUR_PROJECT_ID
```

認証時のアカウント: `etukobamasatyan@gmail.com`

### ステップ 2: Compute Engine API の有効化

```bash
# Compute Engine API を有効化
gcloud services enable compute.googleapis.com
```

または、GCP Console で有効化:
https://console.cloud.google.com/apis/library/compute.googleapis.com

### ステップ 3: 設定ファイルの作成

```bash
# infra ディレクトリに移動
cd infra

# terraform.tfvars.example をコピー
cp terraform.tfvars.example terraform.tfvars

# terraform.tfvars を編集
vim terraform.tfvars
```

**最低限必要な設定:**

```hcl
project_id = "your-gcp-project-id"  # 必須: あなたの GCP プロジェクト ID
```

### ステップ 4: Terraform の初期化

```bash
# Terraform の初期化（プロバイダーのダウンロード）
terraform init
```

### ステップ 5: 実行プランの確認

```bash
# どのようなリソースが作成されるか確認
terraform plan
```

### ステップ 6: インフラの作成

```bash
# リソースを作成
terraform apply

# 確認プロンプトで "yes" と入力
```

作成されるリソース:
- Compute Engine インスタンス × 4台（デフォルト）
- ファイアウォールルール（SSH、IPFS ポート）
- （オプション）VPC ネットワーク
- （オプション）静的 IP アドレス

### ステップ 7: 出力情報の確認

```bash
# 作成されたインスタンス情報を表示
terraform output

# SSH コマンドを表示
terraform output ssh_commands

# 詳細情報を表示
terraform output instance_details
```

## インスタンスへの接続

### 方法 1: gcloud コマンド（推奨）

```bash
# 自動的に SSH キーが設定される
gcloud compute ssh ipfs-bench-node-1 --zone=asia-northeast1-a
```

### 方法 2: 標準 SSH（SSH キーを設定した場合）

```bash
# 外部 IP を確認
terraform output external_ips

# SSH で接続
ssh ubuntu@EXTERNAL_IP
```

## ベンチマークの実行

### インスタンスにログイン後

```bash
# 1. リポジトリをクローン（自動クローンされていない場合）
git clone https://github.com/your-username/ipfs_bench.git
cd ipfs_bench

# 2. Docker が動作しているか確認
docker ps

# 3. Docker Compose で IPFS ノードを起動
docker-compose up -d

# 4. ネットワーク制限を適用（オプション）
export BANDWIDTH_RATE="10mbit"
export NETWORK_DELAY="50ms"
export PACKET_LOSS="1"
sudo ./container-init/setup-router-tc.sh

# 5. ベンチマークを実行
./run_bench_10nodes.sh

# 6. 結果を確認
ls -lh test-results/
```

## コスト見積もり

### デフォルト設定（4ノード、n1-standard-2）

**オンデマンドの場合:**
- インスタンス: ¥0.095/時間 × 4台 = ¥0.38/時間
- ディスク: 30GB × 4台 × ¥0.04/月 ≈ ¥0.16/日
- ネットワーク: ¥0.12/GB（送信）

**8時間のベンチマーク:**
- インスタンス: ¥3.04
- ディスク: ¥0.05
- ネットワーク（50GB想定）: ¥6.00
- **合計: 約 ¥9〜¥10**

### プリエンプティブ VM の場合（約 80% 削減）

`terraform.tfvars` で設定:
```hcl
use_preemptible = true
```

**8時間のベンチマーク: 約 ¥2〜¥3**

**注意:** プリエンプティブ VM は 24 時間以内に強制終了される可能性があります。

## インフラの削除

### すべてのリソースを削除

```bash
# リソースを削除
terraform destroy

# 確認プロンプトで "yes" と入力
```

### 一時停止（課金を抑える）

```bash
# インスタンスを停止（ディスク代のみ課金）
gcloud compute instances stop ipfs-bench-node-1 --zone=asia-northeast1-a

# 再開
gcloud compute instances start ipfs-bench-node-1 --zone=asia-northeast1-a
```

## カスタマイズ

### ノード数を変更

```hcl
# terraform.tfvars
node_count = 8  # 8台に変更
```

### マシンタイプを変更

```hcl
# terraform.tfvars
machine_type = "n1-standard-4"  # 4 vCPUs, 15 GB
```

### リージョンを変更

```hcl
# terraform.tfvars
region = "us-central1"       # アメリカ中部
zone   = "us-central1-a"
```

### 静的 IP を使用

```hcl
# terraform.tfvars
use_static_ip = true
```

### 自動でリポジトリをクローン

```hcl
# terraform.tfvars
repo_url = "https://github.com/your-username/ipfs_bench.git"
```

### セキュリティ強化（IP 制限）

```hcl
# terraform.tfvars
allowed_ip_ranges = ["YOUR_IP_ADDRESS/32"]  # あなたの IP のみ許可
```

自分の IP を確認:
```bash
curl ifconfig.me
```

## トラブルシューティング

### エラー: "Compute Engine API has not been used"

```bash
# API を有効化
gcloud services enable compute.googleapis.com
```

### エラー: "insufficient authentication scopes"

```bash
# アプリケーションのデフォルト認証情報を再設定
gcloud auth application-default login
```

### エラー: "quota exceeded"

- GCP Console で quota を確認
- 必要に応じて quota 増加をリクエスト
- または `node_count` を減らす

### SSH 接続できない

```bash
# ファイアウォールルールを確認
gcloud compute firewall-rules list

# インスタンスの状態を確認
gcloud compute instances list

# シリアルポートの出力を確認（起動ログ）
gcloud compute instances get-serial-port-output ipfs-bench-node-1 --zone=asia-northeast1-a
```

## Terraform コマンドリファレンス

```bash
# 初期化
terraform init

# フォーマット
terraform fmt

# 検証
terraform validate

# プラン確認
terraform plan

# 適用
terraform apply

# 特定のリソースのみ作成
terraform apply -target=google_compute_instance.ipfs_nodes[0]

# 出力表示
terraform output

# 状態確認
terraform show

# リソース一覧
terraform state list

# 削除
terraform destroy
```

## ディレクトリ構造

```
infra/
├── main.tf                      # メイン設定（リソース定義）
├── variables.tf                 # 変数定義
├── outputs.tf                   # 出力定義
├── terraform.tfvars.example     # 設定例
├── terraform.tfvars             # 実際の設定（git ignore）
├── README.md                    # このファイル
└── .terraform/                  # Terraform キャッシュ（自動生成）
```

## セキュリティのベストプラクティス

1. **terraform.tfvars を git にコミットしない**
   - `.gitignore` に追加済み
   - プロジェクト ID などの機密情報が含まれる

2. **IP アドレスを制限する**
   - `allowed_ip_ranges` を自分の IP に制限

3. **SSH キーを適切に管理**
   - パスフレーズ付きの SSH キーを使用
   - 秘密鍵は安全に保管

4. **使用後は削除する**
   - `terraform destroy` で確実にリソースを削除
   - 課金を避ける

5. **最小権限の原則**
   - 必要最小限のポートのみ開放
   - 不要なサービスは無効化

## 参考リンク

- [Terraform GCP Provider ドキュメント](https://registry.terraform.io/providers/hashicorp/google/latest/docs)
- [GCP Compute Engine 価格](https://cloud.google.com/compute/pricing)
- [gcloud コマンドリファレンス](https://cloud.google.com/sdk/gcloud/reference)
- [IPFS ドキュメント](https://docs.ipfs.tech/)

## サポート

問題が発生した場合:
1. このREADMEのトラブルシューティングセクションを確認
2. `terraform plan` でエラーメッセージを確認
3. GCP Console でリソースの状態を確認
4. プロジェクトの Issues で質問
