#!/usr/bin/env bash
set -euo pipefail

SYNCTHING_CONFIG_DIR="${SYNCTHING_CONFIG_DIR:-/opt/data/syncthing/config}"
SYNCTHING_DATA_DIR="${SYNCTHING_DATA_DIR:-/opt/data/syncthing/state}"
SYNCTHING_HOME_DIR="${SYNCTHING_HOME_DIR:-/opt/data/syncthing}"

command -v syncthing >/dev/null 2>&1 || {
  echo "ERROR: syncthing not found. Install it first (apt-get install -y syncthing)." >&2
  exit 1
}

mkdir -p "$SYNCTHING_HOME_DIR" "$SYNCTHING_CONFIG_DIR" "$SYNCTHING_DATA_DIR" /opt/logs
export HOME="$SYNCTHING_HOME_DIR"

if [[ ! -f "${SYNCTHING_CONFIG_DIR}/config.xml" || ! -f "${SYNCTHING_CONFIG_DIR}/cert.pem" || ! -f "${SYNCTHING_CONFIG_DIR}/key.pem" ]]; then
  syncthing generate --config "$SYNCTHING_CONFIG_DIR" --no-default-folder
fi

exec syncthing serve \
  --config "$SYNCTHING_CONFIG_DIR" \
  --data "$SYNCTHING_DATA_DIR" \
  --gui-address "127.0.0.1:8384" \
  --no-browser \
  --no-default-folder \
  --no-upgrade
