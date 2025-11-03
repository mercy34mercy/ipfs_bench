# GCP Compute Engine への SSH 接続方法

## 2つの接続方法

### 方法1: gcloud compute ssh（推奨・簡単）⭐

**特徴:**
- SSH鍵を自動管理（何もしなくてOK）
- 初回接続時に自動的に鍵ペアを生成
- 公開鍵をインスタンスに自動配置
- **設定不要で使える**

**メリット:**
- 簡単（1コマンドで接続）
- 鍵管理が自動
- GCPのIAM権限で制御

**デメリット:**
- gcloud CLIが必要
- GCPプロジェクトへのアクセス権限が必要

### 方法2: 標準 ssh コマンド

**特徴:**
- 自分でSSH鍵を用意
- terraform.tfvars で公開鍵を指定
- 標準のsshコマンドで接続

**メリット:**
- 既存のSSH鍵を使える
- scp、rsyncなどの標準ツールが使いやすい
- ポートフォワーディングが柔軟

**デメリット:**
- 事前に鍵ペアの生成が必要
- terraform.tfvarsへの公開鍵の登録が必要

## 方法1: gcloud compute ssh（推奨）

### 使い方

```bash
# 基本形
gcloud compute ssh インスタンス名 --zone=ゾーン名 --project=プロジェクトID

# 実際の例
gcloud compute ssh ipfs-bench-node-1 --zone=asia-northeast1-a --project=research-383706
```

### 初回接続時の流れ

```bash
$ gcloud compute ssh ipfs-bench-node-1 --zone=asia-northeast1-a --project=research-383706

# 初回のみ表示される
WARNING: The private SSH key file for gcloud does not exist.
WARNING: The public SSH key file for gcloud does not exist.
WARNING: You do not have an SSH key for gcloud.
WARNING: Generating SSH keys...

# 鍵の生成を確認
Do you want to continue (Y/n)? Y

# パスフレーズを設定（推奨）または空欄でEnter
Enter passphrase (empty for no passphrase):
Enter same passphrase again:

# 公開鍵がインスタンスに追加される
Updating instance ssh metadata...
Updated [https://www.googleapis.com/compute/v1/projects/research-383706/zones/asia-northeast1-a/instances/ipfs-bench-node-1].

# 接続完了！
Welcome to Ubuntu 22.04.3 LTS (GNU/Linux 5.15.0-1045-gcp x86_64)

ubuntu@ipfs-bench-node-1:~$
```

### 生成されるファイル

```bash
# 鍵の保存場所
~/.ssh/google_compute_engine       # 秘密鍵
~/.ssh/google_compute_engine.pub   # 公開鍵
~/.ssh/google_compute_known_hosts  # known_hosts
```

### terraform.tfvars の設定（方法1の場合）

```hcl
# 何も設定しなくてOK
ssh_user       = "ubuntu"
ssh_public_key = ""  # 空欄のまま
```

### Terraform output から直接コピペ

```bash
# SSH コマンドを表示
terraform output ssh_commands

# 出力例
[
  "gcloud compute ssh ipfs-bench-node-1 --zone=asia-northeast1-a --project=research-383706",
  "gcloud compute ssh ipfs-bench-node-2 --zone=asia-northeast1-a --project=research-383706",
  "gcloud compute ssh ipfs-bench-node-3 --zone=asia-northeast1-a --project=research-383706",
  "gcloud compute ssh ipfs-bench-node-4 --zone=asia-northeast1-a --project=research-383706"
]

# コピペして実行
gcloud compute ssh ipfs-bench-node-1 --zone=asia-northeast1-a --project=research-383706
```

## 方法2: 標準 ssh コマンド

### ステップ1: SSH鍵ペアの生成

```bash
# 新しい鍵ペアを生成
ssh-keygen -t rsa -b 4096 -C "etukobamasatyan@gmail.com" -f ~/.ssh/gcp-ipfs-bench

# パスフレーズを設定（推奨）
Enter passphrase (empty for no passphrase):
Enter same passphrase again:

# 生成されるファイル
~/.ssh/gcp-ipfs-bench      # 秘密鍵
~/.ssh/gcp-ipfs-bench.pub  # 公開鍵
```

### ステップ2: 公開鍵の内容を確認

```bash
# 公開鍵の内容を表示
cat ~/.ssh/gcp-ipfs-bench.pub

# 出力例
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDExampleKeyContent... etukobamasatyan@gmail.com
```

### ステップ3: terraform.tfvars に公開鍵を設定

```hcl
# terraform.tfvars
ssh_user       = "ubuntu"
ssh_public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDExampleKeyContent... etukobamasatyan@gmail.com"
```

または環境変数で指定:

```bash
# 公開鍵を環境変数に設定
export TF_VAR_ssh_public_key="$(cat ~/.ssh/gcp-ipfs-bench.pub)"

# terraform apply
terraform apply
```

### ステップ4: SSH接続

```bash
# 外部IPアドレスを確認
terraform output external_ips

# 出力例
[
  "34.84.123.45",
  "34.84.123.46",
  "34.84.123.47",
  "34.84.123.48"
]

# SSH接続
ssh -i ~/.ssh/gcp-ipfs-bench ubuntu@34.84.123.45
```

### SSH config の設定（オプション）

```bash
# ~/.ssh/config に追加
cat >> ~/.ssh/config << 'EOF'

# IPFS Bench Nodes
Host ipfs-bench-1
    HostName 34.84.123.45
    User ubuntu
    IdentityFile ~/.ssh/gcp-ipfs-bench

Host ipfs-bench-2
    HostName 34.84.123.46
    User ubuntu
    IdentityFile ~/.ssh/gcp-ipfs-bench

Host ipfs-bench-3
    HostName 34.84.123.47
    User ubuntu
    IdentityFile ~/.ssh/gcp-ipfs-bench

Host ipfs-bench-4
    HostName 34.84.123.48
    User ubuntu
    IdentityFile ~/.ssh/gcp-ipfs-bench
EOF
```

これで短いコマンドで接続可能:

```bash
# 短縮形で接続
ssh ipfs-bench-1
ssh ipfs-bench-2
```

## 比較表

| 項目 | gcloud compute ssh | 標準 ssh |
|------|-------------------|----------|
| **設定の簡単さ** | ⭐⭐⭐⭐⭐ 超簡単 | ⭐⭐⭐ やや面倒 |
| **鍵の管理** | 自動 | 手動 |
| **terraform.tfvars設定** | 不要 | 必要 |
| **gcloud CLI** | 必要 | 不要 |
| **IAM権限** | 必要 | 不要（鍵があればOK） |
| **ポートフォワーディング** | 可能 | 簡単 |
| **scp/rsync** | やや面倒 | 簡単 |

## 実用例

### ファイルのアップロード

#### gcloud compute scp

```bash
# ローカル → リモート
gcloud compute scp ./local-file.txt ipfs-bench-node-1:~/ \
  --zone=asia-northeast1-a \
  --project=research-383706

# ディレクトリごと
gcloud compute scp --recurse ./local-dir/ ipfs-bench-node-1:~/ \
  --zone=asia-northeast1-a \
  --project=research-383706

# リモート → ローカル
gcloud compute scp ipfs-bench-node-1:~/remote-file.txt ./ \
  --zone=asia-northeast1-a \
  --project=research-383706
```

#### 標準 scp

```bash
# ローカル → リモート
scp -i ~/.ssh/gcp-ipfs-bench ./local-file.txt ubuntu@34.84.123.45:~/

# ディレクトリごと
scp -i ~/.ssh/gcp-ipfs-bench -r ./local-dir/ ubuntu@34.84.123.45:~/

# リモート → ローカル
scp -i ~/.ssh/gcp-ipfs-bench ubuntu@34.84.123.45:~/remote-file.txt ./
```

### ポートフォワーディング

#### gcloud compute ssh

```bash
# ポート5001をローカルの5001にフォワード
gcloud compute ssh ipfs-bench-node-1 \
  --zone=asia-northeast1-a \
  --project=research-383706 \
  -- -L 5001:localhost:5001

# ローカルでIPFS APIにアクセス可能
curl http://localhost:5001/api/v0/id
```

#### 標準 ssh

```bash
# ポート5001をローカルの5001にフォワード
ssh -i ~/.ssh/gcp-ipfs-bench -L 5001:localhost:5001 ubuntu@34.84.123.45

# ローカルでIPFS APIにアクセス可能
curl http://localhost:5001/api/v0/id
```

### コマンドの実行（SSH経由）

#### gcloud compute ssh

```bash
# コマンドを実行して終了
gcloud compute ssh ipfs-bench-node-1 \
  --zone=asia-northeast1-a \
  --project=research-383706 \
  --command="docker ps"

# 複数コマンド
gcloud compute ssh ipfs-bench-node-1 \
  --zone=asia-northeast1-a \
  --project=research-383706 \
  --command="cd ipfs_bench && docker-compose up -d && docker ps"
```

#### 標準 ssh

```bash
# コマンドを実行して終了
ssh -i ~/.ssh/gcp-ipfs-bench ubuntu@34.84.123.45 "docker ps"

# 複数コマンド
ssh -i ~/.ssh/gcp-ipfs-bench ubuntu@34.84.123.45 \
  "cd ipfs_bench && docker-compose up -d && docker ps"
```

## 推奨設定

### 初心者・お手軽派: gcloud compute ssh

```hcl
# terraform.tfvars
ssh_user       = "ubuntu"
ssh_public_key = ""  # 空欄
```

**使い方:**
```bash
# そのまま接続
gcloud compute ssh ipfs-bench-node-1 --zone=asia-northeast1-a --project=research-383706
```

### 上級者・柔軟性重視: 標準 ssh

```hcl
# terraform.tfvars
ssh_user       = "ubuntu"
ssh_public_key = "ssh-rsa AAAAB3NzaC1yc2E... etukobamasatyan@gmail.com"
```

**使い方:**
```bash
# SSH config で短縮
ssh ipfs-bench-1
```

## トラブルシューティング

### エラー: Permission denied (publickey)

**原因:**
- SSH鍵が正しくない
- ユーザー名が間違っている

**解決策:**

```bash
# gcloud の場合: 鍵を再生成
rm ~/.ssh/google_compute_engine*
gcloud compute ssh ipfs-bench-node-1 --zone=asia-northeast1-a --project=research-383706

# 標準 ssh の場合: 公開鍵を確認
cat ~/.ssh/gcp-ipfs-bench.pub
# terraform.tfvars の ssh_public_key と一致するか確認
```

### エラー: Connection timed out

**原因:**
- ファイアウォールでポート22が開いていない
- インスタンスが起動していない

**解決策:**

```bash
# インスタンスの状態を確認
gcloud compute instances list --project=research-383706

# ファイアウォールルールを確認
gcloud compute firewall-rules list --project=research-383706 | grep ssh

# ファイアウォールを確認（terraform で自動作成されているはず）
terraform state show google_compute_firewall.ipfs_firewall
```

### エラー: No such instance

**原因:**
- インスタンス名が間違っている
- ゾーンが間違っている

**解決策:**

```bash
# インスタンス一覧を確認
gcloud compute instances list --project=research-383706

# terraform output で正しいコマンドを確認
terraform output ssh_commands
```

## セキュリティのベストプラクティス

### 1. パスフレーズ付きSSH鍵を使用

```bash
# 鍵生成時にパスフレーズを設定
ssh-keygen -t rsa -b 4096 -C "email@example.com" -f ~/.ssh/gcp-ipfs-bench
Enter passphrase: ********  # 強力なパスフレーズ
```

### 2. IP制限を設定

```hcl
# terraform.tfvars
allowed_ip_ranges = ["YOUR_IP/32"]  # 自分のIPのみ許可
```

自分のIPを確認:
```bash
curl ifconfig.me
```

### 3. SSH鍵の権限を設定

```bash
# 秘密鍵のパーミッションを制限
chmod 600 ~/.ssh/gcp-ipfs-bench
chmod 600 ~/.ssh/google_compute_engine

# 公開鍵
chmod 644 ~/.ssh/gcp-ipfs-bench.pub
chmod 644 ~/.ssh/google_compute_engine.pub
```

### 4. 不要な鍵を削除

```bash
# GCPのSSH鍵メタデータから古い鍵を削除
gcloud compute project-info describe --project=research-383706
```

## まとめ

### おすすめ: gcloud compute ssh

**理由:**
- 設定不要
- 鍵管理が自動
- 簡単

**terraform.tfvars:**
```hcl
ssh_user       = "ubuntu"
ssh_public_key = ""  # 空欄でOK
```

**接続方法:**
```bash
gcloud compute ssh ipfs-bench-node-1 --zone=asia-northeast1-a --project=research-383706
```

これで準備完了です！
