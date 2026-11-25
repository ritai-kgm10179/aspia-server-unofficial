#!/bin/sh
# 被動式健康檢查腳本：確認 PID 1 程序與 TCP 監聽連接埠是否正常，不額外產生連線日誌。
set -eu

# shellcheck source=/usr/local/lib/aspia/lib-ini.sh
. /usr/local/lib/aspia/lib-ini.sh

mode="${1:-}"
cfg_port=""

case "$mode" in
  router)
    expected_comm="aspia_router"
    cfg_file="${ASPIA_ROUTER_CONFIG_FILE:-/etc/aspia/router.conf}"
    if [ -f "$cfg_file" ]; then
      cfg_port="$(ini_get "$cfg_file" client port)"
    fi
    port="${cfg_port:-${ASPIA_ROUTER_CLIENT_PORT:-8062}}"
    ;;
  relay)
    expected_comm="aspia_relay"
    cfg_file="${ASPIA_RELAY_CONFIG_FILE:-/etc/aspia/relay.conf}"
    if [ -f "$cfg_file" ]; then
      cfg_port="$(ini_get "$cfg_file" peer port)"
    fi
    port="${cfg_port:-${ASPIA_RELAY_PORT:-8070}}"
    ;;
  *)
    printf 'Usage: %s <router|relay>\n' "$0" >&2
    exit 1
    ;;
esac

if [ ! -r /proc/1/comm ]; then
  printf 'Cannot inspect /proc/1/comm\n' >&2
  exit 1
fi

actual_comm="$(tr -d '\r\n' < /proc/1/comm)"
if [ "$actual_comm" != "$expected_comm" ]; then
  printf 'Unexpected PID 1 process: %s (expected %s)\n' "$actual_comm" "$expected_comm" >&2
  exit 1
fi

case "$port" in
  ''|*[!0-9]*)
    printf 'Invalid port: %s\n' "$port" >&2
    exit 1
    ;;
esac

hex_port="$(printf '%04X' "$port")"
listening="0"

# 檢查 /proc/net/tcp 與 /proc/net/tcp6 中是否有狀態為 0A (TCP_LISTEN) 的目標連接埠
for proc_net in /proc/net/tcp /proc/net/tcp6; do
  if [ -r "$proc_net" ]; then
    if awk -v hex="$hex_port" '
      FNR > 1 && $4 == "0A" && $2 ~ (":" hex "$") { found = 1; exit 0 }
      END { exit (found ? 0 : 1) }
    ' "$proc_net"; then
      listening="1"
      break
    fi
  fi
done

if [ "$listening" != "1" ]; then
  printf '%s is not listening on TCP port %s (hex %s)\n' "$expected_comm" "$port" "$hex_port" >&2
  exit 1
fi

exit 0
