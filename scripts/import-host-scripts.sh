#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

usage() {
  cat <<'EOF'
Usage:
  import-host-scripts.sh [--termux-home <path>] [--magisk-module-dir <path>] [--termux-cache-dir <path>]

Defaults:
  --termux-home      <TERMUX_HOME>
  --magisk-module-dir /data/adb/modules/easytier_magisk
  --termux-cache-dir <termux-home>/.cache

Description:
  Import host startup/maintenance scripts into /opt/ops/host for Git tracking.
EOF
}

TERMUX_HOME="<TERMUX_HOME>"
MAGISK_MODULE_DIR="/data/adb/modules/easytier_magisk"
TERMUX_CACHE_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --termux-home)
      TERMUX_HOME="${2:-}"
      shift 2
      ;;
    --magisk-module-dir)
      MAGISK_MODULE_DIR="${2:-}"
      shift 2
      ;;
    --termux-cache-dir)
      TERMUX_CACHE_DIR="${2:-}"
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

if [[ -z "$TERMUX_CACHE_DIR" ]]; then
  TERMUX_CACHE_DIR="${TERMUX_HOME}/.cache"
fi

HOST_ROOT="${OPS_REPO}/host"
mkdir -p \
  "${HOST_ROOT}/termux/boot" \
  "${HOST_ROOT}/termux/bin" \
  "${HOST_ROOT}/debian/sbin" \
  "${HOST_ROOT}/magisk/easytier/config"

copy_if_exists() {
  local src="$1"
  local dst="$2"
  local mode="${3:-0755}"
  if [[ -f "$src" ]]; then
    install -m "$mode" "$src" "$dst"
    log "imported: ${src} -> ${dst}"
  else
    log "skip missing: ${src}"
  fi
}

copy_magisk_or_cache() {
  local module_rel="$1"
  local cache_rel="$2"
  local dst="$3"
  local mode="${4:-0755}"
  local module_src="${MAGISK_MODULE_DIR}/${module_rel}"
  local cache_src="${TERMUX_CACHE_DIR}/${cache_rel}"

  if [[ -f "$module_src" ]]; then
    install -m "$mode" "$module_src" "$dst"
    log "imported: ${module_src} -> ${dst}"
    return
  fi

  if [[ -f "$cache_src" ]]; then
    install -m "$mode" "$cache_src" "$dst"
    log "imported(cache): ${cache_src} -> ${dst}"
    return
  fi

  log "skip missing: ${module_src} (fallback: ${cache_src})"
}

copy_if_exists \
  "${TERMUX_HOME}/.config/termux/boot/00-startup.sh" \
  "${HOST_ROOT}/termux/boot/00-startup.sh"
copy_if_exists \
  "${TERMUX_HOME}/.local/bin/start-debian-root.sh" \
  "${HOST_ROOT}/termux/bin/start-debian-root.sh"
copy_if_exists \
  "${TERMUX_HOME}/.local/bin/stop-debian-root.sh" \
  "${HOST_ROOT}/termux/bin/stop-debian-root.sh"
copy_if_exists \
  "${TERMUX_HOME}/.local/bin/debian-persist-mounts-root.sh" \
  "${HOST_ROOT}/termux/bin/debian-persist-mounts-root.sh"
copy_if_exists \
  "${TERMUX_HOME}/.local/bin/start-debian" \
  "${HOST_ROOT}/termux/bin/start-debian"
copy_if_exists \
  "${TERMUX_HOME}/.local/bin/stop-debian" \
  "${HOST_ROOT}/termux/bin/stop-debian"

copy_if_exists \
  "/usr/local/sbin/codex-start-sshd.sh" \
  "${HOST_ROOT}/debian/sbin/codex-start-sshd.sh"
copy_if_exists \
  "/usr/local/sbin/codex-fakeip-guard.sh" \
  "${HOST_ROOT}/debian/sbin/codex-fakeip-guard.sh"

# EasyTier (Magisk outer layer)
copy_magisk_or_cache \
  "service.sh" \
  "service.sh" \
  "${HOST_ROOT}/magisk/easytier/service.sh" \
  "0755"
copy_magisk_or_cache \
  "easytier_core.sh" \
  "easytier_core.sh" \
  "${HOST_ROOT}/magisk/easytier/easytier_core.sh" \
  "0755"
copy_magisk_or_cache \
  "vpn_recover.sh" \
  "vpn_recover.sh" \
  "${HOST_ROOT}/magisk/easytier/vpn_recover.sh" \
  "0755"
copy_magisk_or_cache \
  "hotspot_iprule.sh" \
  "hotspot_iprule.sh" \
  "${HOST_ROOT}/magisk/easytier/hotspot_iprule.sh" \
  "0755"
copy_magisk_or_cache \
  "config/config.toml" \
  "config.toml" \
  "${HOST_ROOT}/magisk/easytier/config/config.toml" \
  "0644"
copy_magisk_or_cache \
  "config/command_args" \
  "command_args" \
  "${HOST_ROOT}/magisk/easytier/config/command_args" \
  "0644"

log "import finished"
