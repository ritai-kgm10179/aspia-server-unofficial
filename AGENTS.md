# 專案開發規範與 AI 代理指引

本檔案定義 `aspia-server-unofficial` 儲存庫的通用專案規範，適用於所有協助維護本專案的開發者與 AI 代理程式。

## 1. 專案定位與架構不變量

- **基底作業系統**：一律採用最新最小化穩定版 `debian:13-slim`（Debian 13 Trixie）。由於上游 `dchapyshev/aspia` 官方釋出的伺服器 `.deb` 為 glibc 連結的 `x86_64`（`amd64`）執行檔，不得任意替換為 Alpine (musl)。
- **單一容器單一服務**：維持 [Dockerfile](Dockerfile) 的多目標設計，將 `aspia_router`（`router` 目標）與 `aspia_relay`（`relay` 目標）拆分建置，不可合併成單一容器多程序。
- **最小權限與安全強化**：
  - 預設以非特權使用者 `aspia`（`UID/GID 1000`）執行，僅於明確以 root 啟動時透過 `setpriv` 降權。
  - [compose.yaml](compose.yaml) 須維持 `read_only: true`、`cap_drop: [ALL]`、`no-new-privileges:true` 與 `tmpfs: [/tmp, /var/log/aspia]`。
  - 金鑰隔離：Router 僅將公開金鑰（`host.pub`、`relay.pub`）複製至 `/run/aspia-keys`，Relay 僅能以 `:ro` 唯讀掛載讀取，嚴禁讓 Relay 存取 `router.conf` 或 `router.db3`。
- **預設建置目標架構**：僅支援 `linux/amd64`，除非上游官方提供 `arm64` `.deb` 套件。

## 2. 語言與文件規範

- **正體中文臺灣地區用語**：所有文件（`README.md`、`AGENTS.md`、`.agents/skills/`）、註解（`.yml`、`.sh`、`Dockerfile`、`compose.yaml`、`.env.example`）與對話回覆，一律使用**正體中文臺灣地區用語**。
  - 標準對照詞彙：`映像檔`、`連接埠`、`伺服器`、`資料庫`、`預設`、`設定`、`儲存庫`、`公開 IP`、`內部網路`、`下載（pull）`、`端對端`、`檢視`、`推送`、`發布`、`登入`、`註解`、`逾時`、`執行`、`即時`、`弱點掃描`、`相依套件`。
- **工具指令標記保護**：不得改動工具解析專用的註解標記，包含 `Dockerfile` 的 `# syntax=docker/dockerfile:1.7`、`# hadolint ignore=DL3008` 與腳本內的 `# shellcheck source=...`。

## 3. 程式碼與格式規範

- **換行字元**：所有檔案一律使用 **LF（`\n`）** 換行，不可包含 CR（`\r`），並與 [`.gitattributes`](.gitattributes) 保持一致。
- **Shell 腳本規範**：
  - `scripts/*.sh` 一律使用嚴格 POSIX `sh`（`#!/bin/sh` + `set -eu`），必須通過 ShellCheck（`-S warning`）檢查。
  - INI 處理須相容 Debian 預設的 `mawk`（不可使用 GNU `awk` 專屬參數如 `-i inplace`）。
- **Dockerfile 規範**：必須通過 Hadolint 檢查；套件安裝須使用 `--no-install-recommends` 並清除 `/var/lib/apt/lists/*`；`ENTRYPOINT` 與 `HEALTHCHECK CMD` 一律使用 JSON 陣列格式。

## 4. Arcane 管理與設定相容性

- 維持 [compose.yaml](compose.yaml) 頂層 `x-arcane` 與服務層 `com.getarcaneapp.arcane.*` 標籤，且不使用已棄用的 `version:` 欄位。
- 預設開啟 `ASPIA_LOG_TO_STDOUT=1`、`ASPIA_LOG_TO_FILE=0`，確保日誌即時輸出至 Arcane Logs。
- 維持 `ASPIA_MANAGE_CONFIG` 雙模式：預設 `true` 只同步環境變數對應欄位（保留 `[smtp]` 等手動區段）；設為 `false` 時完全不修改 `.conf` 檔。
- [scripts/healthcheck.sh](scripts/healthcheck.sh) 須維持被動式檢查（讀取 `/proc/1/comm` 與 `/proc/net/tcp*`），且優先從實際 `.conf` 讀取連接埠。

## 5. 版號、機密資料與授權邊界

- 更新 Aspia 版本時，須同步維護 [VERSION](VERSION) 與 [Dockerfile](Dockerfile) 中的 `ARG ASPIA_VERSION`，不可只改單一檔案。
- 嚴禁將 `.env`、`*.db3`、`*.conf`、`*.pub` 或任何金鑰／憑證納入版控。
- **授權邊界**：本儲存庫原創檔案以 **CC0 1.0 Universal** 釋出；建置後之容器映像檔因內含上游 `dchapyshev/aspia` 執行檔，其 OCI 授權標籤維持 `GPL-3.0-or-later`。
