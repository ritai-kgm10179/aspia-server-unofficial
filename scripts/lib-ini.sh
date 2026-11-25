#!/bin/sh
# Aspia v3 容器共用的日誌輸出、權限降級與 POSIX INI 設定檔讀寫函式庫。

log_info() {
  printf '%s [INFO] %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*"
}

log_warn() {
  printf '%s [WARN] %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*" >&2
}

log_error() {
  printf '%s [ERROR] %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*" >&2
}

# 當容器被明確指定以 root 身分啟動時（例如搭配 PUID/PGID），調整目錄權限後降級為非特權使用者執行。
drop_privs_and_reexec() {
  if [ "$(id -u)" = "0" ]; then
    puid="${PUID:-1000}"
    pgid="${PGID:-1000}"
    for dir in /etc/aspia /var/lib/aspia /var/log/aspia /run/aspia-keys; do
      if [ -d "$dir" ] && [ -w "$dir" ]; then
        chown -R "${puid}:${pgid}" "$dir" 2>/dev/null || true
      fi
    done
    exec setpriv --reuid="$puid" --regid="$pgid" --clear-groups -- "$0" "$@"
  fi
}

# 從 INI 設定檔讀取指定區段與鍵值：ini_get <檔案路徑> <區段> <鍵名稱>
ini_get() {
  _file="$1"
  _sec="$2"
  _key="$3"

  if [ ! -f "$_file" ]; then
    return 0
  fi

  INI_SEC="$_sec" INI_KEY="$_key" awk '
    BEGIN {
      sec = ENVIRON["INI_SEC"]
      key = ENVIRON["INI_KEY"]
      in_sec = 0
    }
    {
      line = $0
      sub(/\r$/, "", line)
      if (line ~ /^[[:space:]]*[;#]/) next
      if (line ~ /^[[:space:]]*\[[^]]+\][[:space:]]*$/) {
        s = line
        sub(/^[[:space:]]*\[/, "", s)
        sub(/\][[:space:]]*$/, "", s)
        in_sec = (s == sec) ? 1 : 0
        next
      }
      if (in_sec) {
        eq = index(line, "=")
        if (eq > 0) {
          k = substr(line, 1, eq - 1)
          sub(/^[[:space:]]+/, "", k)
          sub(/[[:space:]]+$/, "", k)
          if (k == key) {
            v = substr(line, eq + 1)
            sub(/^[[:space:]]+/, "", v)
            sub(/[[:space:]]+$/, "", v)
            print v
            exit 0
          }
        }
      }
    }
  ' "$_file"
}

# 更新或新增 INI 區段內的鍵值對（保留原有註解與其他區段）：ini_set <檔案路徑> <區段> <鍵名稱> <值>
ini_set() {
  _file="$1"
  _sec="$2"
  _key="$3"
  _val="$4"

  if [ ! -f "$_file" ]; then
    : > "$_file"
  fi

  _tmp="$(mktemp /tmp/aspia-ini.XXXXXX)"
  if INI_SEC="$_sec" INI_KEY="$_key" INI_VAL="$_val" awk '
    BEGIN {
      sec = ENVIRON["INI_SEC"]
      key = ENVIRON["INI_KEY"]
      val = ENVIRON["INI_VAL"]
      in_sec = 0
      found_sec = 0
      updated = 0
    }
    {
      line = $0
      sub(/\r$/, "", line)
      if (line ~ /^[[:space:]]*\[[^]]+\][[:space:]]*$/) {
        if (in_sec && !updated) {
          print key "=" val
          updated = 1
        }
        s = line
        sub(/^[[:space:]]*\[/, "", s)
        sub(/\][[:space:]]*$/, "", s)
        if (s == sec) {
          in_sec = 1
          found_sec = 1
        } else {
          in_sec = 0
        }
        print line
        next
      }
      if (in_sec && !updated && line !~ /^[[:space:]]*[;#]/) {
        eq = index(line, "=")
        if (eq > 0) {
          k = substr(line, 1, eq - 1)
          sub(/^[[:space:]]+/, "", k)
          sub(/[[:space:]]+$/, "", k)
          if (k == key) {
            print key "=" val
            updated = 1
            next
          }
        }
      }
      print line
    }
    END {
      if (!found_sec) {
        if (NR > 0) print ""
        print "[" sec "]"
        print key "=" val
      } else if (in_sec && !updated) {
        print key "=" val
      }
    }
  ' "$_file" > "$_tmp"; then
    cat "$_tmp" > "$_file"
    rm -f "$_tmp"
  else
    rm -f "$_tmp"
    return 1
  fi
}
