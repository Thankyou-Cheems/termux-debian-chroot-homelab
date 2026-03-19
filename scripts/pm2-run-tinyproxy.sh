#!/usr/bin/env bash
set -euo pipefail

PROXY_DATA_DIR="${PROXY_DATA_DIR:-/opt/data/tinyproxy}"
PROXY_LOG_DIR="${PROXY_LOG_DIR:-/opt/logs/tinyproxy}"
PROXY_CONF_FILE="${PROXY_CONF_FILE:-${PROXY_DATA_DIR}/tinyproxy.conf}"
PROXY_PORT="${PROXY_PORT:-18888}"
PROXY_LISTEN="${PROXY_LISTEN:-<HOST_IP>}"
PROXY_USER="${PROXY_USER:-root}"
PROXY_GROUP="${PROXY_GROUP:-root}"
PROXY_ALLOW_LIST="${PROXY_ALLOW_LIST:-127.0.0.1,<HOST_IP>/24}"

command -v tinyproxy >/dev/null 2>&1 || {
  echo "ERROR: tinyproxy not found. Install it with: apt-get install -y tinyproxy" >&2
  exit 1
}

mkdir -p "$PROXY_DATA_DIR" "$PROXY_LOG_DIR"

if [[ ! -f "$PROXY_CONF_FILE" ]]; then
  cat > "$PROXY_CONF_FILE" <<EOF
User ${PROXY_USER}
Group ${PROXY_GROUP}
Port ${PROXY_PORT}
Listen ${PROXY_LISTEN}
Timeout 600
LogFile "${PROXY_LOG_DIR}/tinyproxy.log"
LogLevel Info
PidFile "/tmp/tinyproxy.pid"
MaxClients 80
StartServers 4
MinSpareServers 2
MaxSpareServers 8
ConnectPort 443
ConnectPort 80
EOF

  OLD_IFS="$IFS"
  IFS=','
  for allow_item in $PROXY_ALLOW_LIST; do
    allow_item="$(echo "$allow_item" | tr -d '[:space:]')"
    [[ -n "$allow_item" ]] || continue
    printf 'Allow %s\n' "$allow_item" >> "$PROXY_CONF_FILE"
  done
  IFS="$OLD_IFS"
fi

exec tinyproxy -d -c "$PROXY_CONF_FILE"
