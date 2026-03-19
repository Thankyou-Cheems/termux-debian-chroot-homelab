#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

CONFIG_DIR="${DATA_ROOT}/transmission/config"
DOWNLOAD_DIR="${DATA_ROOT}/transmission/data"
INCOMPLETE_DIR="${DATA_ROOT}/transmission/incomplete"
WATCH_DIR="${DATA_ROOT}/transmission/watch"
LOG_DIR="${LOG_ROOT}/transmission"
SECRETS_DIR="${SECRETS_ROOT}/transmission"
SETTINGS_FILE="${CONFIG_DIR}/settings.json"
TRACKERS_FILE="${DATA_ROOT}/bt-trackers/trackers-best.txt"
RPC_USERNAME_FILE="${SECRETS_DIR}/rpc-username.txt"
RPC_PASSWORD_FILE="${SECRETS_DIR}/rpc-password.txt"

require_cmd transmission-daemon
require_cmd openssl

mkdir -p \
  "${CONFIG_DIR}" \
  "${DOWNLOAD_DIR}" \
  "${INCOMPLETE_DIR}" \
  "${WATCH_DIR}" \
  "${LOG_DIR}" \
  "${SECRETS_DIR}"

chmod 700 "${SECRETS_DIR}"

if [[ ! -s "${RPC_USERNAME_FILE}" ]]; then
  printf 'nas\n' > "${RPC_USERNAME_FILE}"
  chmod 600 "${RPC_USERNAME_FILE}"
fi

if [[ ! -s "${RPC_PASSWORD_FILE}" ]]; then
  openssl rand -hex 16 > "${RPC_PASSWORD_FILE}"
  chmod 600 "${RPC_PASSWORD_FILE}"
fi

if [[ ! -f "${SETTINGS_FILE}" ]]; then
  rpc_username="$(tr -d '\r\n' < "${RPC_USERNAME_FILE}")"
  rpc_password="$(tr -d '\r\n' < "${RPC_PASSWORD_FILE}")"
  default_trackers=""

  if [[ -s "${TRACKERS_FILE}" ]]; then
    default_trackers="$(
      awk '
        BEGIN { first = 1 }
        {
          gsub(/\\/,"\\\\");
          gsub(/"/,"\\\"");
          if (!first) {
            printf "\\n";
          }
          printf "%s", $0;
          first = 0;
        }
      ' "${TRACKERS_FILE}"
    )"
  fi

  cat > "${SETTINGS_FILE}" <<EOF
{
  "bind-address-ipv4": "0.0.0.0",
  "bind-address-ipv6": "::",
  "default-trackers": "${default_trackers}",
  "dht-enabled": true,
  "download-dir": "${DOWNLOAD_DIR}",
  "download-queue-enabled": true,
  "download-queue-size": 5,
  "idle-seeding-limit-enabled": false,
  "incomplete-dir": "${INCOMPLETE_DIR}",
  "incomplete-dir-enabled": true,
  "lpd-enabled": false,
  "message-level": 2,
  "peer-limit-global": 200,
  "peer-limit-per-torrent": 50,
  "peer-port": 51413,
  "peer-port-random-on-start": false,
  "pex-enabled": true,
  "port-forwarding-enabled": false,
  "preallocation": 1,
  "preferred_transport": "utp",
  "ratio-limit-enabled": false,
  "rename-partial-files": true,
  "rpc-authentication-required": true,
  "rpc-bind-address": "127.0.0.1",
  "rpc-enabled": true,
  "rpc-host-whitelist-enabled": false,
  "rpc-password": "${rpc_password}",
  "rpc-port": 9091,
  "rpc-url": "/transmission/",
  "rpc-username": "${rpc_username}",
  "rpc-whitelist-enabled": false,
  "script-torrent-done-enabled": false,
  "script-torrent-done-seeding-enabled": false,
  "seed-queue-enabled": false,
  "speed-limit-down-enabled": false,
  "speed-limit-up-enabled": false,
  "start-added-torrents": true,
  "start_paused": false,
  "trash-original-torrent-files": false,
  "umask": "022",
  "utp-enabled": true,
  "watch-dir": "${WATCH_DIR}",
  "watch-dir-enabled": true,
  "watch-dir-force-generic": false
}
EOF
  chmod 600 "${SETTINGS_FILE}"
fi

rpc_username="$(tr -d '\r\n' < "${RPC_USERNAME_FILE}")"
rpc_password="$(tr -d '\r\n' < "${RPC_PASSWORD_FILE}")"
rpc_username_json="${rpc_username//\\/\\\\}"
rpc_username_json="${rpc_username_json//\"/\\\"}"
rpc_password_json="${rpc_password//\\/\\\\}"
rpc_password_json="${rpc_password_json//\"/\\\"}"
tmp_settings_file="$(mktemp)"

awk \
  -v rpc_username="${rpc_username_json}" \
  -v rpc_password="${rpc_password_json}" '
    BEGIN {
      updated_user = 0
      updated_password = 0
    }
    {
      if ($0 ~ /"rpc-password":/) {
        print "  \"rpc-password\": \"" rpc_password "\","
        updated_password = 1
        next
      }
      if ($0 ~ /"rpc-username":/) {
        print "  \"rpc-username\": \"" rpc_username "\","
        updated_user = 1
        next
      }
      print
    }
    END {
      if (!updated_user || !updated_password) {
        exit 1
      }
    }
  ' "${SETTINGS_FILE}" > "${tmp_settings_file}"

install -m 0600 "${tmp_settings_file}" "${SETTINGS_FILE}"
rm -f "${tmp_settings_file}"

exec transmission-daemon \
  --foreground \
  --config-dir "${CONFIG_DIR}" \
  --log-level=info
