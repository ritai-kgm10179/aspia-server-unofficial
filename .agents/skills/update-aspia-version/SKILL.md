---
name: update-aspia-version
description: >-
  當使用者要求檢查、升級或指定 Aspia v3 版本（或驗證自動化更新工作流程）時使用此技能。
  涵蓋上游套件確認、VERSION 與 Dockerfile 同步、設定變更檢查及發布觸發流程。
---

# 更新 Aspia v3 版本

## 執行步驟

1. **確認上游版本與 `.deb` 資產**
   - 查詢 `https://api.github.com/repos/dchapyshev/aspia/releases`（或透過 GitHub CLI／Web 搜尋），確認目標 `3.x` 非草稿、非預先發布版本同時具備 `aspia-router-*-(x86_64|amd64).deb` 與 `aspia-relay-*-(x86_64|amd64).deb`。
   - 確認上游發布說明是否有新增或異動 `router.conf`、`relay.conf` 鍵值或預設連接埠。

2. **同步版號檔案**
   - 更新 [VERSION](../../../VERSION) 為目標純版號（不含 `v` 前綴，例如 `3.4.3`，結尾單一 LF 換行）。
   - 同步更新 [Dockerfile](../../../Dockerfile) 頂端的 `ARG ASPIA_VERSION=<版本>`。
   - 若上游變更設定格式或預設連接埠，同步調整 `scripts/entrypoint-router.sh`、`scripts/entrypoint-relay.sh`、`compose.yaml`、`.env.example` 與 `README.md`。

3. **驗證與發布**
   - 執行 `validate-repo` 技能完成本機檢查。
   - 若直接透過 GitHub 自動化流程更新，前往 GitHub Actions 執行 `.github/workflows/auto-update.yml`（可指定 `target_version` 或勾選 `force_rebuild`）：偵測到版號或基底映像檔變動時，會自動建立或更新 `chore/auto-update` Pull Request 以通過 `main` 分支 Ruleset 檢查，合併至 `main` 後由 `build-and-publish.yml` 發布映像檔並建立 GitHub Release；若無檔案異動且勾選 `force_rebuild`，則會直接呼叫 `build-and-publish.yml` 重新建置並發布（需確認 Hadolint、ShellCheck、Compose 冒煙測試與 Trivy 掃描皆通過）。
