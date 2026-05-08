# GitHub Actions Runner Docker

這個專案用來建立與啟動 GitHub Actions self-hosted runner 容器。

## 內容

- `Dockerfile`: 建立 amd64 runner 映像
- `Dockerfile.arm64`: 建立 arm64 runner 映像
- `entrypoint.sh`: 容器啟動時自動註冊並執行 runner
- `docker-compose.yml`: 使用 Docker Compose 啟動 runner
- `.dockerignore`: 排除不需要加入 build context 的檔案

## 功能

- 使用 Ubuntu 22.04
- 下載 GitHub Actions Runner `2.333.1`
- 建立 `runner` 使用者
- `runner` 具有 `sudo` 權限且免密碼
- 容器啟動時自動執行 `config.sh`
- 容器停止時嘗試移除 runner 設定

## 需求

- Docker
- Docker Compose
- 下列其中一種 GitHub 憑證來源：
  - GitHub repository / organization runner registration token（舊模式）
  - GitHub PAT（動態 bootstrap 模式）

## 設定方式

建議先複製 `.env.example` 為 `.env`：

```bash
cp .env.example .env
```

再依照你要的模式填入環境變數。

### 模式 A：舊式手動 registration token

```env
RUNNER_URL=https://github.com/your-org/your-repo
RUNNER_TOKEN=your_short_lived_registration_token
RUNNER_NAME=
RUNNER_LABELS=docker,linux,x64
RUNNER_GROUP=Default
RUNNER_WORKDIR=_work
```

### 模式 B：動態 bootstrap（推薦）

```env
RUNNER_URL=https://github.com/your-org/your-repo
GITHUB_TOKEN=your_long_lived_github_pat
RUNNER_NAME=
RUNNER_LABELS=docker,linux,x64
RUNNER_GROUP=Default
RUNNER_WORKDIR=_work
```

在動態 bootstrap 模式下，container 會在每次啟動時：

1. 使用 `GITHUB_TOKEN` 呼叫 GitHub API
2. 動態申請新的短效 registration token
3. 若偵測到既有 runner 設定，先嘗試移除舊註冊
4. 再用新的短效 token 重新完成 runner 註冊

### 參數說明

- `RUNNER_URL`: GitHub repository 或 organization URL
- `RUNNER_TOKEN`: GitHub 提供的短效 runner registration token，若有提供會優先使用
- `GITHUB_TOKEN`: 用來向 GitHub API 動態申請短效 runner registration token 的長效憑證
- `RUNNER_NAME`: runner 名稱；若留空則預設使用 container hostname，較適合 scale
- `RUNNER_LABELS`: runner labels，多個用逗號分隔
- `RUNNER_GROUP`: runner group 名稱
- `RUNNER_WORKDIR`: runner 工作目錄

## 建立與啟動

### 使用 Docker Compose

```bash
docker compose up -d --build
```

### 啟動多個 runner

```bash
docker compose up -d --build --scale github-runner=2
```

建議在 scale 模式下不要手動指定固定 `RUNNER_NAME`，讓 container hostname 自動成為唯一 runner 名稱。

預設情況下，每次 container 啟動都會重新註冊 runner（`FORCE_RECONFIGURE=true`），避免重用一次性的舊 registration token 或殘留舊 runner 狀態。

### 查看狀態

```bash
docker compose ps
docker compose logs -f
```

### 停止

```bash
docker compose down
```

## 單獨使用 docker build / run

### 建立映像

```bash
docker build -t my-github-runner .
```

### 啟動容器（舊模式）

```bash
docker run -d \
  --name github-runner \
  -e RUNNER_URL="https://github.com/your-org/your-repo" \
  -e RUNNER_TOKEN="your_runner_registration_token" \
  -e RUNNER_LABELS="docker,linux,x64" \
  -e RUNNER_GROUP="Default" \
  -e RUNNER_WORKDIR="_work" \
  my-github-runner
```

### 啟動容器（動態 bootstrap 模式）

```bash
docker run -d \
  --name github-runner \
  -e RUNNER_URL="https://github.com/your-org/your-repo" \
  -e GITHUB_TOKEN="your_long_lived_github_pat" \
  -e RUNNER_LABELS="docker,linux,x64" \
  -e RUNNER_GROUP="Default" \
  -e RUNNER_WORKDIR="_work" \
  my-github-runner
```

## Docker Hub 發佈 workflow

專案已包含 GitHub Actions workflow：`.github/workflows/docker-publish.yml`

### 觸發條件

- 推送 git tag `v*` 時自動 build 並 push 到 Docker Hub
- 可從 GitHub Actions 頁面手動執行 `workflow_dispatch`

### 需要設定的 GitHub Secrets

請在 GitHub repository secrets 設定：

- `DOCKERHUB_USERNAME`
- `DOCKERHUB_TOKEN`

建議 `DOCKERHUB_TOKEN` 使用 Docker Hub access token，不要直接使用帳號密碼。

### 需要修改的 image 名稱

workflow 內目前設定為：

```yaml
env:
  IMAGE_NAME: wrenth04/action-runner
```

如果你之後要改成其他 Docker Hub image 名稱，可直接修改這個值，例如：

```yaml
env:
  IMAGE_NAME: your-dockerhub-user/github-runner
```

### 發佈的 tags

workflow 會先分別使用：

- `Dockerfile` 建立 `linux/amd64`
- `Dockerfile.arm64` 建立 `linux/arm64`

接著合併成同一組 multi-arch tags。

當你推送例如 `v1.2.3` 時，workflow 會發佈：

- `1.2.3`
- `1.2`
- `1`
- `sha-<commit>`

手動觸發時會發佈：

- `sha-<commit>`
- `manual-<commit>`

### 驗證方式

1. 在 GitHub 建立並推送 tag，例如：

```bash
git tag v0.1.0
git push origin v0.1.0
```

2. 到 GitHub Actions 確認 workflow 成功
3. 到 Docker Hub 檢查對應 tags 是否已建立
4. 拉取映像驗證：

```bash
docker pull your-dockerhub-user/github-runner:0.1.0
```

## 注意事項

- `RUNNER_TOKEN` 具有時效性，過期後需要重新產生
- `GITHUB_TOKEN` 是長期憑證，請使用最小必要權限並妥善保管
- 建議不要把真實 token 直接提交到版本控制
- 建議使用 `.env` 管理敏感資訊
- 預設每次 container 啟動都會重新註冊 runner；若你真的想沿用既有本地設定，可自行將 `FORCE_RECONFIGURE=false`
- 容器停止時會 best-effort 嘗試移除 GitHub 端 runner 註冊，但若 remove token 失敗，仍可能留下殘留 runner 紀錄
- 若你刪除容器或不再使用該 runner，仍建議在 GitHub 端確認是否有殘留 runner 紀錄
- 目前動態 bootstrap 第一版支援 GitHub.com 的 repo / org URL；若是 GitHub Enterprise Server，可透過 `GITHUB_API_URL` 覆寫 API base URL

## 建議改進

如果要進一步優化，可以再加入：

- volume 掛載 `_work`
- healthcheck
- GitHub App-based bootstrap
- just-in-time (JIT) runner config
