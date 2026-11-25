---
name: validate-repo
description: >-
  在修改任何 Dockerfile、Shell 腳本、Compose 設定、GitHub Actions 工作流程或文件後，
  於提交或開立 PR 前執行完整的本機與 CI 相容性檢查時使用此技能。
---

# 驗證專案完整性與品質規範

## 本機檢查步驟（Windows / Linux 通用）

1. **換行字元與編碼檢查**
   - 確認所有文字檔（`scripts/*.sh`、`Dockerfile`、`compose.yaml`、`.github/workflows/*.yml`、`VERSION`、`.base-digest`、`README.md`、`AGENTS.md`、`.agents/skills/*/SKILL.md`）皆使用純 LF（`\n`），無 CR（`\r`）字元。

2. **設定檔與工具指令標記檢查**
   - 使用 `ConvertFrom-Json`（PowerShell）或 `jq` 驗證 `arcane/template.json` 為合法 JSON。
   - 確認所有 `.yml` / `.yaml` 檔案不含 Tab 縮排；若環境安裝有 Python PyYAML，執行 `yaml.safe_load` 檢查。
   - 確認 `Dockerfile` 保留 `# syntax=docker/dockerfile:1.7` 與 `# hadolint ignore=DL3008`；確認 `scripts/*.sh` 保留 `# shellcheck source=/usr/local/lib/aspia/lib-ini.sh`。

3. **臺灣地區用語與機密檔案檢查**
   - 檢視新增或修改的中文說明與註解，確保使用正體中文臺灣地區用語（參照 `AGENTS.md`）。
   - 執行 `git status --short` 確認沒有意外追蹤 `.env`、`*.db3`、`*.conf`、`*.pub` 等敏感或執行期檔案。

## 容器與 Linux 環境檢查（於 CI 或 Linux 主機執行）

1. 執行 `hadolint Dockerfile` 與 `shellcheck -S warning scripts/*.sh`。
2. 執行 `docker compose config -q` 驗證 Compose 語法。
3. 依 `.github/workflows/build-and-publish.yml` 的煙霧測試流程建置 `router` 與 `relay` 映像檔，啟動後驗證兩者皆為 `healthy`、PID 1 為非特權使用者 `1000`、根檔案系統為唯讀，且 Relay 無法讀取 `router.conf` 與 `router.db3`。
