#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

usage() {
  cat <<'EOF'
Usage:
  install-host-scripts.sh [--termux-home <path>] [--backup-dir <path>] [--magisk-module-dir <path>]

Defaults:
  --termux-home       <TERMUX_HOME>
  --backup-dir        /opt/backup/host-script-backups
  --magisk-module-dir /data/adb/modules/easytier_magisk

Description:
  Install tracked host scripts from /opt/ops/host back to runtime locations.
EOF
}

TERMUX_HOME="<TERMUX_HOME>"
BACKUP_DIR="/opt/backup/host-script-backups"
MAGISK_MODULE_DIR="/data/adb/modules/easytier_magisk"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --termux-home)
      TERMUX_HOME="${2:-}"
      shift 2
      ;;
    --backup-dir)
      BACKUP_DIR="${2:-}"
      shift 2
      ;;
    --magisk-module-dir)
      MAGISK_MODULE_DIR="${2:-}"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

HOST_ROOT="${OPS_REPO}/host"
STAMP="$(timestamp)"
BACKUP_PATH="${BACKUP_DIR}/${STAMP}"
mkdir -p "$BACKUP_PATH"

install_if_exists() {
  local src="$1"
  local dst="$2"
  local mode="${3:-0755}"

  if [[ ! -f "$src" ]]; then
    log "skip missing tracked file: ${src}"
    return
  fi

  mkdir -p "$(dirname "$dst")"
  if [[ -f "$dst" || -L "$dst" ]]; then
    cp -a "$dst" "${BACKUP_PATH}/$(basename "$dst").bak"
  fi
  install -m "$mode" "$src" "$dst"
  log "installed: ${src} -> ${dst}"
}

install_if_magisk_available() {
  local src="$1"
  local rel_dst="$2"
  local mode="${3:-0755}"

  if [[ ! -d "$MAGISK_MODULE_DIR" ]]; then
    log "skip magisk install (module dir missing): ${MAGISK_MODULE_DIR}"
    return
  fi
  install_if_exists "$src" "${MAGISK_MODULE_DIR}/${rel_dst}" "$mode"
}

install_if_exists \
  "${HOST_ROOT}/termux/boot/00-startup.sh" \
  "${TERMUX_HOME}/.config/termux/boot/00-startup.sh"
install_if_exists \
  "${HOST_ROOT}/termux/bin/start-debian-root.sh" \
  "${TERMUX_HOME}/.local/bin/start-debian-root.sh"
install_if_exists \
  "${HOST_ROOT}/termux/bin/stop-debian-root.sh" \
  "${TERMUX_HOME}/.local/bin/stop-debian-root.sh"
install_if_exists \
  "${HOST_ROOT}/termux/bin/debian-persist-mounts-root.sh" \
  "${TERMUX_HOME}/.local/bin/debian-persist-mounts-root.sh"
install_if_exists \
  "${HOST_ROOT}/termux/bin/start-debian" \
  "${TERMUX_HOME}/.local/bin/start-debian"
install_if_exists \
  "${HOST_ROOT}/termux/bin/stop-debian" \
  "${TERMUX_HOME}/.local/bin/stop-debian"

install_if_exists \
  "${HOST_ROOT}/debian/sbin/codex-start-sshd.sh" \
  "/usr/local/sbin/codex-start-sshd.sh"
install_if_exists \
  "${HOST_ROOT}/debian/sbin/codex-fakeip-guard.sh" \
  "/usr/local/sbin/codex-fakeip-guard.sh"

# EasyTier (Magisk outer layer)
install_if_magisk_available \
  "${HOST_ROOT}/magisk/easytier/service.sh" \
  "service.sh" \
  "0755"
install_if_magisk_available \
  "${HOST_ROOT}/magisk/easytier/easytier_core.sh" \
  "easytier_core.sh" \
  "0755"
install_if_magisk_available \
  "${HOST_ROOT}/magisk/easytier/vpn_recover.sh" \
  "vpn_recover.sh" \
  "0755"
install_if_magisk_available \
  "${HOST_ROOT}/magisk/easytier/hotspot_iprule.sh" \
  "hotspot_iprule.sh" \
  "0755"
install_if_magisk_available \
  "${HOST_ROOT}/magisk/easytier/config/config.toml" \
  "config/config.toml" \
  "0644"
install_if_magisk_available \
  "${HOST_ROOT}/magisk/easytier/config/command_args" \
  "config/command_args" \
  "0644"

log "install finished; backups at ${BACKUP_PATH}"
