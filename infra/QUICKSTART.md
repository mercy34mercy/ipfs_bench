# クイックスタートガイド

## 5分で GCP に IPFS ベンチマーク環境を構築

### 1. 前提条件の確認

```bash
# gcloud がインストールされているか確認
gcloud version

# Terraform がインストールされているか確認
terraform version
```

インストールされていない場合:
```bash
# macOS
brew install --cask google-cloud-sdk
brew install terraform
```

### 2. Google Cloud 認証

```bash
# Google アカウントで認証（etukobamasatyan@gmail.com を使用）
gcloud auth login

# Terraform 用の認証
gcloud auth application-default login

# プロジェクトを設定（あなたの GCP プロジェクト ID に置き換え）
gcloud config set project YOUR_PROJECT_ID
```

### 3. Compute Engine API の有効化

```bash
gcloud services enable compute.googleapis.com
```

### 4. Terraform 設定

```bash
# infra ディレクトリに移動
cd infra

# 設定ファイルをコピー
cp terraform.tfvars.example terraform.tfvars

# 設定を編集（最低限 project_id を設定）
vim terraform.tfvars
```

**terraform.tfvars（最小設定）:**
```hcl
project_id = "your-gcp-project-id"  # あなたのプロジェクト ID
```

### 5. インフラ作成

```bash
# 初期化
terraform init

# プレビュー
terraform plan

# 作成（確認プロンプトで "yes" と入力）
terraform apply
```

### 6. 接続情報の確認

```bash
# SSH コマンドを表示
terraform output ssh_commands

# または
terraform output quick_start_instructions
```

### 7. インスタンスに接続

```bash
# 自動的に表示された SSH コマンドを使用
gcloud compute ssh ipfs-bench-node-1 --zone=asia-northeast1-a --project=YOUR_PROJECT_ID
```

### 8. ベンチマーク実行

インスタンスに接続後:

```bash
# リポジトリをクローン（自動クローンされていない場合）
git clone https://github.com/your-username/ipfs_bench.git
cd ipfs_bench

# Docker Compose で起動
docker-compose up -d

# ベンチマーク実行
./run_bench_10nodes.sh
```

### 9. 後片付け

```bash
# infra ディレクトリで実行
terraform destroy

# 確認プロンプトで "yes" と入力
```

## 完了！

これで GCP 上に IPFS ベンチマーク環境が構築されました。

---

## よくある設定例

### 例1: プリエンプティブ VM（コスト削減）

```hcl
# terraform.tfvars
project_id = "your-project-id"
use_preemptible = true  # 約80%コスト削減
```

### 例2: ノード数を変更

```hcl
# terraform.tfvars
project_id = "your-project-id"
node_count = 8  # 8ノードに増やす
```

### 例3: マシンスペックを上げる

```hcl
# terraform.tfvars
project_id = "your-project-id"
machine_type = "n1-standard-4"  # 4 vCPUs, 15 GB
```

### 例4: 自動でリポジトリをクローン

```hcl
# terraform.tfvars
project_id = "your-project-id"
repo_url = "https://github.com/your-username/ipfs_bench.git"
```

### 例5: IP アドレス制限（セキュリティ強化）

```bash
# 自分の IP を確認
curl ifconfig.me
```

```hcl
# terraform.tfvars
project_id = "your-project-id"
allowed_ip_ranges = ["YOUR_IP/32"]  # あなたの IP のみ許可
```

---

## トラブルシューティング

### エラー: "API has not been used"

```bash
gcloud services enable compute.googleapis.com
```

### エラー: "insufficient authentication scopes"

```bash
gcloud auth application-default login
```

### SSH 接続できない

```bash
# ファイアウォールルールを確認
gcloud compute firewall-rules list

# インスタンスの状態を確認
gcloud compute instances list
```

---

## コスト目安

**デフォルト設定（4ノード、n1-standard-2、8時間）:**
- オンデマンド: 約 ¥9〜¥10
- プリエンプティブ: 約 ¥2〜¥3

**使い終わったら必ず `terraform destroy` を実行しましょう！**
