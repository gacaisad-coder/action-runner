# GitHub Runner 動態 Bootstrap 最終實作計劃

## 目標

將 `action-runner` 改造成支援 **多 runner / 可 scale / 動態取得 registration token** 的 GitHub self-hosted runner 容器方案。

最終要達成：

- 可以在同一台主機上用 `docker compose --scale` 啟動多個 runner
- 每個 runner container 啟動時自行向 GitHub API 申請短效 registration token
- 不需要人工為每個 runner 預先分配不同 token
- 保留單 runner 的相容路徑，避免破壞現有用法
- 文件要清楚描述 PAT-based bootstrap，並保留未來升級 GitHub App / JIT 的空間

---

## 現況問題

目前專案存在以下限制：

1. `docker-compose.yml` 使用固定 `container_name`
   - 會直接阻礙 `docker compose --scale`

2. `docker-compose.yml` 寫死 `RUNNER_NAME`
   - 多個 runner 會在 GitHub 註冊時撞名

3. `entrypoint.sh` 強依賴外部提供 `RUNNER_TOKEN`
   - 這是短效 token，不適合拿來做多副本長期配置

4. 文件目前偏向單一 runner 的手動註冊模式
   - 尚未提供動態 bootstrap 的操作方式

---

## 最終設計

### 啟動流程

容器啟動流程調整為：

1. 啟動 container
2. 讀取 runner 基本設定（URL、labels、group、workdir）
3. 若有提供 `RUNNER_TOKEN`，走舊模式直接註冊
4. 若未提供 `RUNNER_TOKEN`，則改用長期 GitHub 憑證向 GitHub API 申請短效 registration token
5. 以取得的 token 執行 `config.sh`
6. 啟動 `run.sh`

### 設計原則

- registration token 是短效憑證，不寫死於 compose
- 長期憑證只用於換取短效 token
- runner 名稱預設使用 container hostname，避免副本撞名
- 多副本共用同一個 service，而不是靠複製多個 service 維護
- 保留手動 `RUNNER_TOKEN` fallback，便於除錯與回退

---

## 採用方案

### 第一版正式實作：PAT-based dynamic bootstrap

本次實作先採用 **GitHub PAT** 作為長期憑證來源。

原因：

- 實作最快、最直接
- 易於驗證 bootstrap 架構是否可行
- 後續可平滑升級成 GitHub App 模式

### 未來升級空間

文件與程式結構要預留未來替換成：

- GitHub App installation token flow
- GitHub JIT runner config flow

但本次不需要把 GitHub App / JIT 一次做完。

---

## GitHub API 方向

本次 repository-level runner 的動態 bootstrap，預期使用：

- `POST /repos/{owner}/{repo}/actions/runners/registration-token`

若未來支援 org-level runner，則延伸到：

- `POST /orgs/{org}/actions/runners/registration-token`

程式結構應避免把 API 路徑寫死成只有 repo 模式，方便後續擴充。

---

## 檔案修改範圍

### 1. `docker-compose.yml`

#### 修改目標

- 移除 `container_name`
- 不再強制寫死 `RUNNER_NAME`
- 保留單一 `github-runner` service 結構
- 改成適合 `docker compose --scale` 的設定
- 引導使用者透過 `.env` 或環境變數提供長期憑證

#### 預期結果

- `docker compose up -d --scale github-runner=2` 可以建立多個副本
- 每個副本都能靠 entrypoint 自行完成 bootstrap

### 2. `entrypoint.sh`

#### 修改目標

重構目前邏輯：

- 檢查 `RUNNER_URL`
- `RUNNER_NAME` 預設為 `hostname`
- 若 `RUNNER_TOKEN` 存在：沿用舊模式
- 若 `RUNNER_TOKEN` 不存在：改呼叫 bootstrap 函式 / 腳本
- bootstrap 取得 token 後再執行 `config.sh`
- 避免把敏感 token 明文輸出到 log

#### 預期結果

- 同一套 entrypoint 同時支援舊模式與新模式
- 多副本情況下每個 container 都能獨立向 GitHub API 取得 token

### 3. 新增 bootstrap 腳本

建議新增例如：

- `scripts/get-registration-token.sh`

#### 職責

- 解析 `RUNNER_URL`
- 判斷 repo-level / org-level
- 用長期憑證呼叫 GitHub API
- 取得 registration token
- 把 token 輸出給 entrypoint 使用

#### 建議要求

- 不將 token 寫入持久化檔案
- 錯誤訊息可讀，但不要洩漏秘密
- 對 API 失敗保留合理的非零 exit code

### 4. `README.md`

#### 修改目標

補齊以下內容：

- 單 runner 模式
- scale 模式
- 動態 bootstrap 的設定方式
- `RUNNER_TOKEN` fallback 模式
- `GITHUB_TOKEN` 的需求與安全注意事項
- 之後可升級 GitHub App / JIT 的說明

### 5. 其他必要檔案

視實作需要可新增：

- `.env.example`
- `scripts/` 目錄說明
- 測試或驗證腳本

---

## 環境變數介面設計

### 基本設定

- `RUNNER_URL`
- `RUNNER_NAME`（選填，預設 hostname）
- `RUNNER_LABELS`
- `RUNNER_GROUP`
- `RUNNER_WORKDIR`

### 舊模式（相容）

- `RUNNER_TOKEN`

### 新模式（本次主路徑）

- `GITHUB_TOKEN`

### 未來預留（本次可不實作完整邏輯，但文件可保留方向）

- `GITHUB_APP_ID`
- `GITHUB_APP_PRIVATE_KEY`
- `GITHUB_APP_INSTALLATION_ID`

---

## 安全要求

1. 不可把真實 token 提交到 repo
2. 不可在 log 中輸出完整 `RUNNER_TOKEN` 或 `GITHUB_TOKEN`
3. README 必須明確提醒使用者以環境變數或 `.env` 提供秘密
4. bootstrap 腳本只輸出註冊所需 token，不做多餘持久化
5. 錯誤處理時只顯示必要資訊

---

## 驗收標準

### 功能驗收

1. 單 runner 舊模式仍可使用
2. 未提供 `RUNNER_TOKEN` 時，若有 `GITHUB_TOKEN`，可成功 bootstrap
3. 移除 `container_name` 後，compose 可支援 `--scale`
4. 多個副本不會因 `RUNNER_NAME` 固定而撞名
5. README 可讓使用者理解如何啟用動態 bootstrap

### 驗證方式

至少完成以下驗證：

1. shell 語法檢查（例如 `bash -n`）
2. README / compose / script 的一致性檢查
3. 如可行，做最小 mock 或 dry-run 驗證 URL 解析邏輯
4. 若無法在本地用真實 GitHub token 完整驗證，要明確記錄限制

---

## 建議實作步驟

1. 先調整 `docker-compose.yml` 結構，使其可 scale
2. 重構 `entrypoint.sh`，加入 fallback + bootstrap 流程
3. 新增 `scripts/get-registration-token.sh`
4. 補上 `.env.example` 與 `README.md`
5. 做基本驗證
6. 回報尚未覆蓋的真實環境驗證缺口

---

## 本次要交付的實作內容

1. 可合併的程式碼修改
2. 最終版實作計劃文件（本文件）
3. 使用說明更新
4. 基本驗證結果
5. 若有未完成或風險點，要清楚列出
