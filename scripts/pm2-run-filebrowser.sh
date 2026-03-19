#!/usr/bin/env bash
set -euo pipefail

FILEBROWSER_BIN="${FILEBROWSER_BIN:-/opt/apps/filebrowser/bin/filebrowser}"
FILEBROWSER_DATA_DIR="${FILEBROWSER_DATA_DIR:-/opt/data/filebrowser}"
FILEBROWSER_ROOT_DIR="${FILEBROWSER_ROOT_DIR:-${FILEBROWSER_DATA_DIR}/root}"
FILEBROWSER_DB_FILE="${FILEBROWSER_DB_FILE:-${FILEBROWSER_DATA_DIR}/filebrowser.db}"
FILEBROWSER_ADDRESS="${FILEBROWSER_ADDRESS:-127.0.0.1}"
FILEBROWSER_PORT="${FILEBROWSER_PORT:-8095}"
FILEBROWSER_BASEURL="${FILEBROWSER_BASEURL:-/files}"
FILEBROWSER_USERNAME_FILE="${FILEBROWSER_USERNAME_FILE:-/opt/secrets/filebrowser/admin-username.txt}"
FILEBROWSER_PASSWORD_FILE="${FILEBROWSER_PASSWORD_FILE:-/opt/secrets/filebrowser/admin-password.txt}"

command -v mountpoint >/dev/null 2>&1 || {
  echo "ERROR: mountpoint not found" >&2
  exit 1
}

[[ -x "$FILEBROWSER_BIN" ]] || {
  echo "ERROR: missing filebrowser binary: $FILEBROWSER_BIN" >&2
  echo "Install it with: bash /opt/ops/scripts/install-filebrowser.sh" >&2
  exit 1
}

ensure_bind_mount() {
  local src="$1"
  local dst="$2"
  [[ -d "$src" ]] || return 0
  mkdir -p "$dst"
  if mountpoint -q "$dst"; then
    return 0
  fi
  mount --bind "$src" "$dst"
}

ensure_credentials() {
  mkdir -p "$(dirname "$FILEBROWSER_USERNAME_FILE")"
  if [[ ! -s "$FILEBROWSER_USERNAME_FILE" ]]; then
    printf 'admin\n' > "$FILEBROWSER_USERNAME_FILE"
    chmod 600 "$FILEBROWSER_USERNAME_FILE"
  fi
  if [[ ! -s "$FILEBROWSER_PASSWORD_FILE" ]]; then
    openssl rand -hex 16 > "$FILEBROWSER_PASSWORD_FILE"
    chmod 600 "$FILEBROWSER_PASSWORD_FILE"
  fi
}

ensure_layout() {
  mkdir -p "$FILEBROWSER_DATA_DIR" "$FILEBROWSER_ROOT_DIR"
  mkdir -p "$FILEBROWSER_ROOT_DIR/downloads" "$FILEBROWSER_ROOT_DIR/sync" "$FILEBROWSER_ROOT_DIR/inbox" "$FILEBROWSER_ROOT_DIR/mobile"
  ensure_bind_mount /opt/data/aria2/data "$FILEBROWSER_ROOT_DIR/downloads/aria2"
  ensure_bind_mount /opt/data/transmission/data "$FILEBROWSER_ROOT_DIR/downloads/transmission"
  ensure_bind_mount /opt/data/transmission/watch "$FILEBROWSER_ROOT_DIR/inbox/torrents"
  ensure_bind_mount /opt/data/syncthing/sync "$FILEBROWSER_ROOT_DIR/sync/syncthing"
  ensure_bind_mount /mnt/termux-home "$FILEBROWSER_ROOT_DIR/mobile/termux-home"
}

ensure_database() {
  if [[ ! -f "$FILEBROWSER_DB_FILE" ]]; then
    "$FILEBROWSER_BIN" config init \
      -d "$FILEBROWSER_DB_FILE" \
      -a "$FILEBROWSER_ADDRESS" \
      -p "$FILEBROWSER_PORT" \
      -b "$FILEBROWSER_BASEURL" \
      -r "$FILEBROWSER_ROOT_DIR"
    return 0
  fi

  "$FILEBROWSER_BIN" config set \
    -d "$FILEBROWSER_DB_FILE" \
    -a "$FILEBROWSER_ADDRESS" \
    -p "$FILEBROWSER_PORT" \
    -b "$FILEBROWSER_BASEURL" \
    -r "$FILEBROWSER_ROOT_DIR"
}

ensure_admin_user() {
  local username password
  username="$(tr -d '\r\n' < "$FILEBROWSER_USERNAME_FILE")"
  password="<REDACTED>"

  if [[ ! -f "$FILEBROWSER_DB_FILE" ]]; then
    "$FILEBROWSER_BIN" users add "$username" "$password" --perm.admin -d "$FILEBROWSER_DB_FILE"
    return 0
  fi

  if ! "$FILEBROWSER_BIN" users ls -d "$FILEBROWSER_DB_FILE" | awk '{print $2}' | grep -Fxq "$username"; then
    "$FILEBROWSER_BIN" users add "$username" "$password" --perm.admin -d "$FILEBROWSER_DB_FILE"
  fi
}

ensure_credentials
ensure_layout
ensure_database
ensure_admin_user

exec "$FILEBROWSER_BIN" \
  -a "$FILEBROWSER_ADDRESS" \
  -p "$FILEBROWSER_PORT" \
  -b "$FILEBROWSER_BASEURL" \
  -r "$FILEBROWSER_ROOT_DIR" \
  -d "$FILEBROWSER_DB_FILE"
