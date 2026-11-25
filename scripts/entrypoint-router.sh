#!/bin/sh
# Aspia v3 Router 容器啟動腳本：負責首次初始化、公開金鑰複製與環境變數同步。
set -eu

# shellcheck source=/usr/local/lib/aspia/lib-ini.sh
. /usr/local/lib/aspia/lib-ini.sh

drop_privs_and_reexec "$@"

ASPIA_ROUTER_CONFIG_FILE="${ASPIA_ROUTER_CONFIG_FILE:-/etc/aspia/router.conf}"
export ASPIA_ROUTER_CONFIG_FILE

ASPIA_LOG_LEVEL="${ASPIA_LOG_LEVEL:-1}"
ASPIA_LOG_TO_STDOUT="${ASPIA_LOG_TO_STDOUT:-1}"
ASPIA_LOG_TO_FILE="${ASPIA_LOG_TO_FILE:-0}"
export ASPIA_LOG_LEVEL ASPIA_LOG_TO_STDOUT ASPIA_LOG_TO_FILE

CONFIG_DIR="$(dirname "$ASPIA_ROUTER_CONFIG_FILE")"
PUBLIC_KEYS_DIR="${ASPIA_PUBLIC_KEYS_DIR:-/run/aspia-keys}"
MANAGE_CONFIG="${ASPIA_MANAGE_CONFIG:-true}"

mkdir -p "$CONFIG_DIR" /var/lib/aspia

# 首次啟動且尚無 router.conf 時，執行初始化產生設定檔、金鑰與一次性管理員密碼
if [ ! -f "$ASPIA_ROUTER_CONFIG_FILE" ]; then
  if [ -f /var/lib/aspia/router.db3 ]; then
    log_error "router.conf is missing at ${ASPIA_ROUTER_CONFIG_FILE}, but /var/lib/aspia/router.db3 already exists."
    log_error "Aspia refuses --create-config when a database already exists. Restore router.conf or remove old db files to re-initialize."
    exit 1
  fi

  log_info "========================================================================="
  log_info "FIRST BOOT: Generating Aspia Router configuration and admin credentials."
  log_info "IMPORTANT: Save the one-time 'admin' password printed below!"
  log_info "========================================================================="

  aspia_router --create-config

  log_info "========================================================================="
  log_info "Router initialization complete. Copy the admin password above now."
  log_info "========================================================================="

  chmod 600 "$ASPIA_ROUTER_CONFIG_FILE" 2>/dev/null || true
fi

# 僅複製公開金鑰（*.pub）至共享目錄，不曝露 router.conf 或資料庫
if [ -d "$PUBLIC_KEYS_DIR" ] && [ -w "$PUBLIC_KEYS_DIR" ]; then
  copied_any="0"
  for pub_name in host.pub relay.pub router.pub; do
    src_pub="${CONFIG_DIR}/${pub_name}"
    if [ -f "$src_pub" ]; then
      cp "$src_pub" "${PUBLIC_KEYS_DIR}/${pub_name}"
      chmod 644 "${PUBLIC_KEYS_DIR}/${pub_name}" 2>/dev/null || true
      copied_any="1"
    fi
  done
  if [ "$copied_any" = "1" ]; then
    log_info "Published public keys to ${PUBLIC_KEYS_DIR} for Relay auto-configuration."
  fi
fi

# 在日誌中印出 host.pub 內容，方便於 Arcane 日誌頁面直接複製使用
if [ -f "${CONFIG_DIR}/host.pub" ]; then
  host_pub="$(tr -d '\r\n' < "${CONFIG_DIR}/host.pub")"
  if [ -n "$host_pub" ]; then
    log_info "Router public key for Hosts/Clients (host.pub): ${host_pub}"
  fi
fi

# 若啟用環境變數管理模式，僅更新對應欄位並保留其餘手動設定（例如 [smtp]）
if [ "$MANAGE_CONFIG" = "true" ]; then
  log_info "Syncing environment configuration to ${ASPIA_ROUTER_CONFIG_FILE}"

  if [ -n "${ASPIA_ROUTER_ACCESS_LOG_DAYS:-}" ]; then
    ini_set "$ASPIA_ROUTER_CONFIG_FILE" router access_log_days "$ASPIA_ROUTER_ACCESS_LOG_DAYS"
  fi

  ini_set "$ASPIA_ROUTER_CONFIG_FILE" host port "${ASPIA_ROUTER_HOST_PORT:-8061}"
  if [ "${ASPIA_ROUTER_HOST_INTERFACE+set}" = "set" ]; then
    ini_set "$ASPIA_ROUTER_CONFIG_FILE" host listen_interface "$ASPIA_ROUTER_HOST_INTERFACE"
  fi
  if [ "${ASPIA_ROUTER_HOST_WHITELIST+set}" = "set" ]; then
    ini_set "$ASPIA_ROUTER_CONFIG_FILE" host white_list "$ASPIA_ROUTER_HOST_WHITELIST"
  fi

  ini_set "$ASPIA_ROUTER_CONFIG_FILE" client port "${ASPIA_ROUTER_CLIENT_PORT:-8062}"
  if [ "${ASPIA_ROUTER_CLIENT_INTERFACE+set}" = "set" ]; then
    ini_set "$ASPIA_ROUTER_CONFIG_FILE" client listen_interface "$ASPIA_ROUTER_CLIENT_INTERFACE"
  fi
  if [ "${ASPIA_ROUTER_CLIENT_WHITELIST+set}" = "set" ]; then
    ini_set "$ASPIA_ROUTER_CONFIG_FILE" client white_list "$ASPIA_ROUTER_CLIENT_WHITELIST"
  fi

  ini_set "$ASPIA_ROUTER_CONFIG_FILE" relay port "${ASPIA_ROUTER_RELAY_PORT:-8063}"
  if [ "${ASPIA_ROUTER_RELAY_INTERFACE+set}" = "set" ]; then
    ini_set "$ASPIA_ROUTER_CONFIG_FILE" relay listen_interface "$ASPIA_ROUTER_RELAY_INTERFACE"
  fi
  if [ "${ASPIA_ROUTER_RELAY_WHITELIST+set}" = "set" ]; then
    ini_set "$ASPIA_ROUTER_CONFIG_FILE" relay white_list "$ASPIA_ROUTER_RELAY_WHITELIST"
  fi

  ini_set "$ASPIA_ROUTER_CONFIG_FILE" stun enabled "${ASPIA_ROUTER_STUN_ENABLED:-1}"
  ini_set "$ASPIA_ROUTER_CONFIG_FILE" stun port "${ASPIA_ROUTER_STUN_PORT:-8065}"
  if [ "${ASPIA_ROUTER_STUN_INTERFACE+set}" = "set" ]; then
    ini_set "$ASPIA_ROUTER_CONFIG_FILE" stun listen_interface "$ASPIA_ROUTER_STUN_INTERFACE"
  fi
else
  log_info "ASPIA_MANAGE_CONFIG=${MANAGE_CONFIG}; skipping INI overrides."
fi

log_info "Starting aspia_router..."
exec aspia_router "$@"
