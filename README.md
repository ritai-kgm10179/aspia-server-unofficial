# Aspia v3 Server Docker (Router + Relay) — Arcane Ready

專為 **GitHub Container Registry (GHCR)** 與 **[Arcane](https://getarcane.app/)** 管理的非官方 **Aspia v3** Docker 映像檔與 Compose 堆疊（Stack），採用最新最小化穩定版 **Debian 13 (`debian:13-slim`)** 建置，並內建**每日自動檢查版本與安全更新並重新發布映像檔**的 GitHub Actions 工作流程。

> [!WARNING]
> **免責聲明**：本專案由 AI 服務產製，非 Aspia 官方維護專案；部署於正式環境前請自行審閱所有腳本與設定，使用請自負風險。

---

## ✨ 設計特色

- **最新最小化基底 OS (`debian:13-slim`)**：直接安裝官方釋出的 Aspia v3 `.deb` 原生套件，兼具最小攻擊面（Arcane / Trivy 弱點掃描友善）與完整相容性。
- **單一容器單一服務架構**：將 `aspia_router`（內含 STUN）與 `aspia_relay` 拆分為獨立的 `router` 與 `relay` 映像檔，符合 Docker 最佳實踐，也能各自擴展或單獨部署外部 Relay。
- **安全強化 (Hardened by Default)**：
  - 非特權使用者 `aspia` (`UID/GID 1000`) 執行，支援 `PUID`/`PGID` 透過 `setpriv` 降權。
  - `read_only: true` 唯讀根檔案系統、`cap_drop: [ALL]`、`no-new-privileges:true`。
  - **最小權限金鑰共享**：Router 僅將公開金鑰（`host.pub`、`relay.pub`）複製到 `/run/aspia-keys`，Relay 以 `:ro` 唯讀掛載自動讀取，完全無法存取 `router.conf` 或 `router.db3`。
- **Arcane 原生整合**：
  - 內建 `x-arcane` 與 `com.getarcaneapp.arcane.*` 標籤（圖示、文件連結、Auto-Updater 延遲設定）。
  - 所有日誌透過 `ASPIA_LOG_TO_STDOUT=1` 直接輸出至 stdout，可在 Arcane Logs 即時檢視。
  - 使用具名磁碟區（Volume），方便透過 Arcane Volume Backups 備份設定與資料庫。
  - 無額外相依套件、零日誌干擾的被動式 `HEALTHCHECK`（檢查 PID 1 與 `/proc/net/tcp` 監聽狀態）。
- **全自動版本追蹤與映像檔更新**：
  - [`.github/workflows/auto-update.yml`](.github/workflows/auto-update.yml) 每日定時檢查 `dchapyshev/aspia` 最新穩定版 `3.x` 與 `debian:13-slim` 基底映像檔 Digest，有更新即自動提交版號、建立 Release 並發布新版映像檔至 GHCR。

---

## 🚀 快速開始（GitHub 設定）

1. 將本專案推送至你的 GitHub 儲存庫，並確認 GitHub Actions 權限已開啟：
   - 前往 **Settings → Actions → General → Workflow permissions**，選擇 **Read and write permissions**。
2. 執行一次 **Actions → Auto-Update Aspia & Base Image → Run workflow**（可勾選 `force_rebuild`）即可自動建置並推送：
   - `ghcr.io/<你的帳號>/aspia-server-unofficial/router:3`
   - `ghcr.io/<你的帳號>/aspia-server-unofficial/relay:3`
3. （建議）前往 GitHub Package 設定頁面確認 `router` 與 `relay` 套件的可見性為 **Public**（若設為 Private，請先在 Arcane 中設定 GHCR Registry 登入憑證）。

---

## 📖 完整使用範例

### 範例 1：在 Arcane 建立專案（建議做法）

1. 在 Arcane 左側選單進入 **Projects → Create**（或使用 **GitOps Sync** 直接同步本 GitHub 儲存庫的 [`compose.yaml`](compose.yaml)）。
2. 將 [`compose.yaml`](compose.yaml) 內容貼入編輯器（或由 GitOps 自動同步），再把以下內容貼入 Arcane 的 **.env Editor**：
   ```dotenv
   # 必填：填入這台主機對外公開的 IP 或網域名稱
   ASPIA_RELAY_PUBLIC_ADDRESS=aspia.example.com

   # 必填：替換為你自己的 GitHub 帳號或組織名稱
   IMAGE_PREFIX=ghcr.io/your-username/aspia-server-unofficial
   ASPIA_ICON_URL=https://raw.githubusercontent.com/your-username/aspia-server-unofficial/main/assets/aspia-icon.svg

   # 選填：追蹤所有 v3.x 版本與安全更新
   ASPIA_IMAGE_TAG=3
   TZ=Asia/Taipei
   ARCANE_UPDATER_ENABLED=true
   ARCANE_UPDATER_DELAY=24
   ```
3. 點擊 **Deploy** 啟動堆疊（Stack）。
4. 進入 Arcane 的 `aspia-router` 容器 **Logs** 頁面，複製僅顯示一次的預設管理員帳密與 `host.pub`：
   ```text
   ==================== LOGIN CREDENTIALS ====================
   User name: admin
   Password: <產生的隨機密碼>
   ===========================================================
   ...
   Router public key for Hosts/Clients (host.pub): 0123456789abcdef...
   ```
   也可透過終端機或 Arcane Web Terminal 檢視：
   ```bash
   docker exec aspia-router cat /etc/aspia/host.pub
   ```
5. 開啟 Aspia Client / Host 設定連線資訊：
   - **Router 位址**：`aspia.example.com`（Host 連接埠 `8061`、Client 連接埠 `8062`）
   - **Router 公鑰**：填入剛剛取得的 `host.pub` 內容
   - Relay 的 `relay.pub` 已由容器透過共用磁碟區自動完成交握，無須手動設定。

---

### 範例 2：從 Windows Aspia v3 移轉既有設定與資料庫

如果你原本在 Windows 上已執行 Aspia v3 Router／Relay，想把帳號、電腦 ID 清單與金鑰直接搬移到這個 Docker 專案：

1. **先停止 Windows 上的服務**（避免 SQLite 資料庫處於寫入或鎖定狀態）：
   ```powershell
   # 在 Windows 系統管理員 PowerShell 執行
   Stop-Service aspia-router, aspia-relay
   ```
2. **取得 Windows 原有檔案**（預設位於 `C:\ProgramData\aspia\`）：
   - Router 資料庫：`router.db3`、`access_log.db3`、`email_queue.db3`
   - Router 設定與金鑰：`router.conf`、`host.pub`、`relay.pub`
   - Relay 設定：`relay.conf`
   > ⚠️ 若原本為舊版 Aspia v2（`router.json` / `relay.json`），無法直接相容，請先升級至 v3。
3. **修改 `compose.yaml` 為本地目錄掛載（Bind Mount）或複製進具名磁碟區**：
   以下示範使用本地資料夾 `./data/` 掛載：
   ```bash
   # 在 Linux 主機建立目錄並放入從 Windows 複製過來的檔案
   mkdir -p ./data/router-config ./data/router-data ./data/relay-config

   # 放入資料庫檔案
   cp router.db3 access_log.db3 email_queue.db3 ./data/router-data/

   # 放入設定檔與公開金鑰
   cp router.conf host.pub relay.pub ./data/router-config/
   cp relay.conf ./data/relay-config/

   # 確認 router.conf 與 relay.conf 的 listen_interface 為空（避免綁定 Windows 舊 IP 導致啟動失敗）
   sed -i 's/^listen_interface=.*/listen_interface=/' ./data/router-config/router.conf ./data/relay-config/relay.conf

   # 設定容器非特權使用者 (UID/GID 1000) 權限
   chown -R 1000:1000 ./data
   chmod 600 ./data/router-config/router.conf ./data/relay-config/relay.conf
   ```
4. 在 `compose.yaml` 將對應磁碟區改為 Bind Mount（`./data/...`）後啟動：
   - 因 `ASPIA_MANAGE_CONFIG=true`（預設），啟動腳本會自動將 `relay.conf` 內的 `[router] address` 從 `127.0.0.1` 更新為 `aspia-router`，並保留所有原有帳號與金鑰。

---

### 範例 3：手動調整 `router.conf` / `relay.conf` 設定檔

本專案支援兩種調整方式：

#### 方式 A：保留大部分自動同步，僅補充進階區段（例如 `[smtp]` 郵件通知）
保持預設 `ASPIA_MANAGE_CONFIG=true`，直接編輯 `router.conf` 加上 `[smtp]` 區段即可。啟動腳本**只會更新環境變數有指定的欄位**，不會覆蓋其他區段。

#### 方式 B：完全由手動管理 `.conf` 檔（停用環境變數覆蓋）
1. 在 Arcane 的 `.env` 編輯器設定：
   ```dotenv
   ASPIA_MANAGE_CONFIG=false
   ```
2. 若想直接從主機文字編輯器修改設定檔，可將 [`compose.yaml`](compose.yaml) 的 `volumes:` 改為本地目錄掛載：
   ```yaml
   services:
     aspia-router:
       volumes:
         - ./config/router:/etc/aspia
         - ./data/router:/var/lib/aspia
         - aspia-public-keys:/run/aspia-keys
     aspia-relay:
       volumes:
         - ./config/relay:/etc/aspia
         - aspia-public-keys:/run/aspia-keys:ro
   ```
3. 修改完設定檔後重新啟動容器即可生效；健康檢查腳本會自動讀取 `.conf` 內的實際連接埠進行檢測（若變更連接埠，記得同步更新 `compose.yaml` 的 `ports:` 對應）。

---

### 範例 4：跨主機額外部署獨立 Relay 節點

若要在另一台 VPS 部署額外的 Relay 來分擔流量：
1. 在主機（Router 端）的 [`compose.yaml`](compose.yaml) 取消 `8063:8063/tcp` 連接埠註解並重新部署。
2. 取得 Router 的 Relay 公鑰：
   ```bash
   docker exec aspia-router cat /etc/aspia/relay.pub
   ```
3. 在另一台 VPS 建立只包含 `aspia-relay` 的 `compose.yaml`：
   ```yaml
   services:
     aspia-relay:
       image: ghcr.io/your-username/aspia-server-unofficial/relay:3
       container_name: aspia-relay-edge
       restart: unless-stopped
       read_only: true
       cap_drop:
         - ALL
       security_opt:
         - no-new-privileges:true
       tmpfs:
         - /tmp
         - /var/log/aspia
       environment:
         TZ: Asia/Taipei
         ASPIA_ROUTER_ADDRESS: router.example.com
         ASPIA_ROUTER_PORT: 8063
         # 跨主機部署時請手動填入剛剛取得的 relay.pub 內容
         ASPIA_ROUTER_PUBLIC_KEY: <填入剛剛取得的 relay.pub 內容>
         ASPIA_RELAY_PUBLIC_ADDRESS: relay2.example.com
         ASPIA_RELAY_PORT: 8070
       ports:
         - "8070:8070/tcp"
       volumes:
         - aspia-relay-config:/etc/aspia

   volumes:
     aspia-relay-config:
   ```

---

### 範例 5：純 Docker CLI 本機建置與執行

若不想依賴 GHCR，想直接於主機本機建置並啟動：

```bash
# 1. 下載專案並準備環境變數檔
git clone https://github.com/your-username/aspia-server-unofficial.git
cd aspia-server-unofficial
cp .env.example .env

# 2. 編輯 .env，至少填入 ASPIA_RELAY_PUBLIC_ADDRESS 與 IMAGE_PREFIX=aspia-local
sed -i 's|^ASPIA_RELAY_PUBLIC_ADDRESS=.*|ASPIA_RELAY_PUBLIC_ADDRESS=你的公開IP或網域|' .env
sed -i 's|^IMAGE_PREFIX=.*|IMAGE_PREFIX=aspia-local|' .env
sed -i 's|^ASPIA_IMAGE_TAG=.*|ASPIA_IMAGE_TAG=3.4.3|' .env

# 3. 使用 Docker Buildx 分別建置 router 與 relay 映像檔
docker build --target router -t aspia-local/router:3.4.3 .
docker build --target relay  -t aspia-local/relay:3.4.3 .

# 4. 啟動服務並檢視首次產生的 admin 密碼
docker compose up -d
docker compose logs -f aspia-router
```

---

## 🔌 連接埠與防火牆一覽

| 服務 | 連接埠 | 協定 | 用途 | 備註 |
| --- | --- | --- | --- | --- |
| `aspia-router` | `8061` | TCP | Aspia Host 連線 | 對外開放 |
| `aspia-router` | `8062` | TCP | Aspia Client 連線 | 對外開放 |
| `aspia-router` | `8063` | TCP | Aspia Relay 連線 | 預設僅於 Docker `aspia-net` 內部網路通訊；若需連接外部獨立 Relay 才需對外開放 |
| `aspia-router` | `8065` | UDP | 內建 STUN 伺服器 | 對外開放（協助 NAT 穿透直連） |
| `aspia-relay` | `8070` | TCP | Peer 資料中繼 | 對外開放 |

---

## ⚙️ 環境變數說明

### 通用與 Arcane 設定

| 變數名稱 | 預設值 | 說明 |
| --- | --- | --- |
| `IMAGE_PREFIX` | `ghcr.io/your-username/aspia-server-unofficial` | GHCR 映像檔路徑前綴 |
| `ASPIA_IMAGE_TAG` | `3` | 追蹤的映像檔標籤（`3` 會自動接收所有 v3.x 版本與安全更新） |
| `ARCANE_UPDATER_ENABLED` | `true` | 是否允許 Arcane Auto-Updater 自動更新 |
| `ARCANE_UPDATER_DELAY` | `24` | Arcane 偵測到新版映像檔後的延遲更新時數（小時） |
| `TZ` | `UTC`（`.env.example` 為 `Asia/Taipei`） | 容器時區 |
| `ASPIA_LOG_LEVEL` | `1` | 日誌等級：`0`=追蹤 (trace)、`1`=資訊 (info)、`2`=警告 (warning)、`3`=錯誤 (error)、`4`=嚴重 (fatal) |
| `ASPIA_LOG_TO_STDOUT` | `1` | 輸出日誌至 stdout（供 Arcane Logs 即時檢視） |
| `ASPIA_LOG_TO_FILE` | `0` | 關閉容器內部寫入檔案日誌 |
| `ASPIA_MANAGE_CONFIG` | `true` | 是否於每次啟動時將環境變數同步寫入 `.conf`；設為 `false` 可完全保留手動修改 |

### Aspia Router (`aspia-router`)

| 變數名稱 | 預設值 | 說明 |
| --- | --- | --- |
| `ASPIA_ROUTER_HOST_PORT` | `8061` | Host 連線埠（TCP） |
| `ASPIA_ROUTER_CLIENT_PORT` | `8062` | Client 連線埠（TCP） |
| `ASPIA_ROUTER_RELAY_PORT` | `8063` | Relay 連線埠（TCP） |
| `ASPIA_ROUTER_STUN_ENABLED` | `1` | 啟用（`1`）或停用（`0`）內建 STUN |
| `ASPIA_ROUTER_STUN_PORT` | `8065` | STUN 監聽埠（UDP） |
| `ASPIA_ROUTER_ACCESS_LOG_DAYS` | `45` | 存取紀錄保留天數（1–365 天） |
| `ASPIA_ROUTER_HOST_WHITELIST` | *(空)* | 允許連線的 Host IP/CIDR 白名單（半形逗號分隔） |
| `ASPIA_ROUTER_CLIENT_WHITELIST` | *(空)* | 允許連線的 Client IP/CIDR 白名單 |
| `ASPIA_ROUTER_RELAY_WHITELIST` | *(空)* | 允許連線的 Relay IP/CIDR 白名單 |

### Aspia Relay (`aspia-relay`)

| 變數名稱 | 預設值 | 說明 |
| --- | --- | --- |
| `ASPIA_RELAY_PUBLIC_ADDRESS` | *(必填)* | 對外公開的 IP 或網域名稱（供 Client/Host 連線） |
| `ASPIA_ROUTER_ADDRESS` | `aspia-router` | Router 主機位址 |
| `ASPIA_ROUTER_PORT` | `8063` | Router 的 Relay 連接埠 |
| `ASPIA_ROUTER_PUBLIC_KEY` | *(空)* | 選填；同一台主機的堆疊會自動從 `/run/aspia-keys/relay.pub` 讀取，跨主機部署獨立 Relay 時才需手動填入 |
| `ASPIA_RELAY_PORT` | `8070` | Peer 資料中繼埠（TCP） |
| `ASPIA_RELAY_MAX_PEERS` | `100` | 最大同時中繼連線數（1–1000） |
| `ASPIA_RELAY_IDLE_TIMEOUT` | `5` | 連線閒置斷線逾時時間（1–60 分鐘） |

---

## 🔄 自動化更新機制說明

- **排程檢查**：[`.github/workflows/auto-update.yml`](.github/workflows/auto-update.yml) 每天 UTC 03:00（台北時間 11:00）自動執行。
- **雙重觸發條件**：
  1. 上游 `dchapyshev/aspia` 發布新的 `3.x` 穩定版（含 `x86_64`/`amd64` `.deb` 套件）。
  2. `debian:13-slim` (`linux/amd64`) 基底映像檔有安全更新（Manifest Digest 變動）。
- **自動化流程**：更新 `VERSION` / `Dockerfile` / `.base-digest` → 提交並建立 GitHub Release → 呼叫 [`build-and-publish.yml`](.github/workflows/build-and-publish.yml) 完成 Hadolint、ShellCheck、Compose 端對端健康檢查測試、Trivy 弱點掃描，最後推送包含 SBOM 與 SLSA Provenance 的新映像檔至 GHCR。
- **搭配 Arcane Auto-Updater**：只要 Compose 中追蹤 `:3` 標籤並保留 `com.getarcaneapp.arcane.updater=true`，Arcane 就會在冷卻期後自動下載（pull）並重建容器。

---

## ⚠️ 架構限制說明

上游 `dchapyshev/aspia` 目前僅官方提供 Linux `x86_64` (`.deb`) 預先編譯伺服器套件，因此本映像檔預設建置目標為 `linux/amd64`。

---

## 📄 授權條款

- **本儲存庫原創檔案**：包含 [Dockerfile](Dockerfile)、[compose.yaml](compose.yaml)、`scripts/*.sh`、GitHub Actions 工作流程、說明文件與圖示資源，皆以 **[CC0 1.0 Universal](LICENSE)** 釋出至公眾領域。
- **建置後之容器映像檔**：映像檔內所包含的上游 [Aspia](https://github.com/dchapyshev/aspia) 執行檔依循 **GPL-3.0-or-later** 授權條款，[Dockerfile](Dockerfile) 中的 `org.opencontainers.image.licenses` 標籤亦維持 `GPL-3.0-or-later`；基底作業系統 Debian 套件則依循各自之原授權條款。
