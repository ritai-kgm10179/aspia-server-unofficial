---
name: arcane-compose-maintenance
description: >-
  當需要調整 compose.yaml、環境變數、連接埠、Arcane 標籤或映像檔設定同步邏輯時使用此技能。
  確保 Arcane 介面整合、雙模式設定同步與 Windows 移轉相容性不被破壞。
---

# 維護 Arcane Compose 與設定同步

## 同步修改原則

新增或變更任何環境變數、連接埠或磁碟區時，須同步檢查以下五個位置：

1. [compose.yaml](../../../compose.yaml)：服務的 `environment`、`ports`、`volumes` 與 Arcane 標籤（`x-arcane` 及 `com.getarcaneapp.arcane.*`）。
2. [.env.example](../../../.env.example)：依「必填」或「選填」分類補充清晰的正體中文臺灣地區用語註解與預設值。
3. `scripts/entrypoint-router.sh` 或 `scripts/entrypoint-relay.sh`：僅在 `ASPIA_MANAGE_CONFIG=true` 時透過 `ini_set` 更新對應欄位，不得覆蓋使用者在 `.conf` 手動設定的其他區段。
4. [scripts/healthcheck.sh](../../../scripts/healthcheck.sh)：若變更 Router Client 連接埠或 Relay Peer 連接埠環境變數名稱，須同步更新健康檢查邏輯（優先讀取 `.conf`，其次讀取環境變數）。
5. [README.md](../../../README.md)：同步更新連接埠一覽表、環境變數說明表與相關使用範例。

## 檢查重點

- 不得在 `compose.yaml` 加入已棄用的 `version:` 頂層欄位。
- 不得破壞 `ASPIA_MANAGE_CONFIG=false` 的完全手動管理模式，以及 `router.conf` / `relay.conf` / `router.db3` 既有檔案存在時跳過 `--create-config` 的行為（確保 Windows Aspia v3 移轉正常運作）。
- 完成修改後執行 `validate-repo` 技能進行驗證。
