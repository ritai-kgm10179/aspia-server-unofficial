#!/bin/sh
# Aspia v3 Relay 容器啟動腳本：負責初始化、自動載入 Router 公鑰與環境變數同步。
set -eu

# shellcheck source=/usr/local/lib/aspia/lib-ini.sh
. /usr/local/lib/aspia/lib-ini.sh

drop_privs_and_reexec "$@"

ASPIA_RELAY_CONFIG_FILE="${ASPIA_RELAY_CONFIG_FILE:-/etc/aspia/relay.conf}"
export ASPIA_RELAY_CONFIG_FILE

ASPIA_LOG_LEVEL="${ASPIA_LOG_LEVEL:-1}"
ASPIA_LOG_TO_STDOUT="${ASPIA_LOG_TO_STDOUT:-1}"
ASPIA_LOG_TO_FILE="${ASPIA_LOG_TO_FILE:-0}"
export ASPIA_LOG_LEVEL ASPIA_LOG_TO_STDOUT ASPIA_LOG_TO_FILE

CONFIG_DIR="$(dirname "$ASPIA_RELAY_CONFIG_FILE")"
MANAGE_CONFIG="${ASPIA_MANAGE_CONFIG:-true}"
KEY_WAIT_SECONDS="${ASPIA_KEY_WAIT_SECONDS:-30}"

mkdir -p "$CONFIG_DIR"

# 首次啟動且尚無 relay.conf 時，執行初始化產生預設設定檔
if [ ! -f "$ASPIA_RELAY_CONFIG_FILE" ]; then
  log_info "Generating initial Aspia Relay configuration at ${ASPIA_RELAY_CONFIG_FILE}"
  aspia_relay --create-config
  chmod 600 "$ASPIA_RELAY_CONFIG_FILE" 2>/dev/null || true
fi

# 優先讀取環境變數指定的公鑰，若未指定則等待共用磁碟區內的 relay.pub
router_public_key="${ASPIA_ROUTER_PUBLIC_KEY:-}"
if [ -z "$router_public_key" ]; then
  key_file="${ASPIA_ROUTER_PUBLIC_KEY_FILE:-/run/aspia-keys/relay.pub}"
  fallback_key_file="/run/aspia-keys/router.pub"
  waited=0

  while [ "$waited" -lt "$KEY_WAIT_SECONDS" ]; do
    if [ -s "$key_file" ]; then
      router_public_key="$(tr -d ' \t\r\n' < "$key_file")"
      break
    fi
    if [ -s "$fallback_key_file" ]; then
      router_public_key="$(tr -d ' \t\r\n' < "$fallback_key_file")"
      break
    fi
    sleep 1
    waited=$((waited + 1))
  done

  if [ -n "$router_public_key" ]; then
    log_info "Loaded Router relay public key automatically from shared keys volume."
  fi
fi

# 若啟用環境變數管理模式，同步 Relay 連線與監聽設定至 relay.conf
if [ "$MANAGE_CONFIG" = "true" ]; then
  log_info "Syncing environment configuration to ${ASPIA_RELAY_CONFIG_FILE}"

  ini_set "$ASPIA_RELAY_CONFIG_FILE" router address "${ASPIA_ROUTER_ADDRESS:-aspia-router}"
  ini_set "$ASPIA_RELAY_CONFIG_FILE" router port "${ASPIA_ROUTER_PORT:-8063}"
  if [ -n "$router_public_key" ]; then
    ini_set "$ASPIA_RELAY_CONFIG_FILE" router public_key "$router_public_key"
  fi

  if [ "${ASPIA_RELAY_LISTEN_INTERFACE+set}" = "set" ]; then
    ini_set "$ASPIA_RELAY_CONFIG_FILE" peer listen_interface "$ASPIA_RELAY_LISTEN_INTERFACE"
  fi
  ini_set "$ASPIA_RELAY_CONFIG_FILE" peer port "${ASPIA_RELAY_PORT:-8070}"
  if [ -n "${ASPIA_RELAY_PUBLIC_ADDRESS:-}" ]; then
    ini_set "$ASPIA_RELAY_CONFIG_FILE" peer public_address "$ASPIA_RELAY_PUBLIC_ADDRESS"
  fi
  if [ -n "${ASPIA_RELAY_MAX_PEERS:-}" ]; then
    ini_set "$ASPIA_RELAY_CONFIG_FILE" peer max_count "$ASPIA_RELAY_MAX_PEERS"
  fi
  if [ -n "${ASPIA_RELAY_IDLE_TIMEOUT:-}" ]; then
    ini_set "$ASPIA_RELAY_CONFIG_FILE" peer idle_timeout "$ASPIA_RELAY_IDLE_TIMEOUT"
  fi
else
  log_info "ASPIA_MANAGE_CONFIG=${MANAGE_CONFIG}; skipping INI overrides."
fi

# 啟動前檢查必要欄位，避免設定不完整時靜默失敗
effective_public_addr="$(ini_get "$ASPIA_RELAY_CONFIG_FILE" peer public_address)"
effective_router_key="$(ini_get "$ASPIA_RELAY_CONFIG_FILE" router public_key)"

if [ -z "$effective_public_addr" ]; then
  log_error "Missing [peer] public_address in ${ASPIA_RELAY_CONFIG_FILE}."
  log_error "Set ASPIA_RELAY_PUBLIC_ADDRESS in your .env file (or Arcane environment variables) to your server's public IP or FQDN."
  exit 1
fi

if [ -z "$effective_router_key" ]; then
  log_error "Missing [router] public_key in ${ASPIA_RELAY_CONFIG_FILE}."
  log_error "Ensure aspia-router is healthy with shared /run/aspia-keys, or set ASPIA_ROUTER_PUBLIC_KEY explicitly."
  exit 1
fi

log_info "Starting aspia_relay (public_address=${effective_public_addr}, router=${ASPIA_ROUTER_ADDRESS:-aspia-router}:${ASPIA_ROUTER_PORT:-8063})..."
exec aspia_relay "$@"
