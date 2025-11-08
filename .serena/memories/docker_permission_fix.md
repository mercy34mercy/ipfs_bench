# Docker Permission Fix

## エラー
```
permission denied while trying to connect to the Docker daemon socket at unix:///var/run/docker.sock
```

## 解決方法（推奨）

ユーザーを docker グループに追加:

```bash
sudo usermod -aG docker $USER
```

実行後、以下のいずれかを実施:
- ログアウトして再ログイン
- 現在のセッションに反映: `newgrp docker`

## 環境
- macOS (darwin)
- Docker Desktop 使用
