#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

usage() {
  cat <<'EOF'
Usage:
  migrate-secrets-to-runtime.sh [--no-export]

Description:
  Move selected credential files out of /opt/data into /opt/secrets and
  replace original paths with symlinks, keeping service-facing paths stable.

Options:
  --no-export    Do not run sync-secrets-repo.sh export after migration
EOF
}

EXPORT_AFTER=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-export)
      EXPORT_AFTER=0
      shift
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

SECRETS_RUNTIME="${SECRETS_ROOT:-${OPS_ROOT}/secrets}"
STAMP="$(timestamp)"
MIGRATION_BACKUP_DIR="${BACKUP_ROOT}/secret-migration/${STAMP}"

mkdir -p "$SECRETS_RUNTIME" "$MIGRATION_BACKUP_DIR"
chmod 700 "$SECRETS_RUNTIME"

is_symlink_to() {
  local path="$1"
  local target="$2"
  [[ -L "$path" ]] && [[ "$(readlink "$path")" == "$target" ]]
}

migrate_file() {
  local src="$1"
  local dst="$2"

  mkdir -p "$(dirname "$src")" "$(dirname "$dst")"

  if is_symlink_to "$src" "$dst"; then
    log "file already linked: ${src} -> ${dst}"
    [[ -f "$dst" ]] || die "broken link source: ${src} -> ${dst}"
    return
  fi

  if [[ -f "$src" && ! -L "$src" ]]; then
    if [[ ! -e "$dst" ]]; then
      mv "$src" "$dst"
      log "migrated file: ${src} -> ${dst}"
    else
      install -m 600 "$src" "${MIGRATION_BACKUP_DIR}/$(basename "$src").from-data.bak"
      install -m 600 "$src" "$dst"
      rm -f "$src"
      log "merged file into existing target: ${src} -> ${dst}"
    fi
  elif [[ ! -e "$src" && ! -e "$dst" ]]; then
    die "both source and target missing: ${src} and ${dst}"
  fi

  ln -sfn "$dst" "$src"
  chmod 600 "$dst"
}

migrate_dir() {
  local src="$1"
  local dst="$2"

  mkdir -p "$(dirname "$src")" "$(dirname "$dst")"

  if is_symlink_to "$src" "$dst"; then
    log "dir already linked: ${src} -> ${dst}"
    [[ -d "$dst" ]] || die "broken link source: ${src} -> ${dst}"
    return
  fi

  if [[ -d "$src" && ! -L "$src" ]]; then
    if [[ ! -e "$dst" ]]; then
      mv "$src" "$dst"
      log "migrated dir: ${src} -> ${dst}"
    else
      tar -C "$src" -cf - . | tar -C "$dst" -xf -
      rm -rf "$src"
      log "merged dir into existing target: ${src} -> ${dst}"
    fi
  elif [[ ! -e "$src" && ! -e "$dst" ]]; then
    die "both source and target missing: ${src} and ${dst}"
  fi

  ln -sfn "$dst" "$src"
  chmod 700 "$dst"
  find "$dst" -type f -exec chmod 600 {} +
}

# ASF credentials
migrate_file "/opt/data/asf/config/ASF.json" "${SECRETS_RUNTIME}/asf/ASF.json"
migrate_file "/opt/data/asf/config/Squad.json" "${SECRETS_RUNTIME}/asf/Squad.json"
migrate_file "/opt/data/asf/config/Squad2.json" "${SECRETS_RUNTIME}/asf/Squad2.json"

# Aria2 credentials
migrate_file "/opt/data/aria2/config/aria2.conf" "${SECRETS_RUNTIME}/aria2/aria2.conf"
migrate_file "/opt/data/aria2/config/rpc-secret.txt" "${SECRETS_RUNTIME}/aria2/rpc-secret.txt"

# MCS manager credentials
migrate_file "/opt/data/mcsmanager/daemon/data/Config/global.json" "${SECRETS_RUNTIME}/mcsmanager/daemon/global.json"
migrate_dir "/opt/data/mcsmanager/web/data/User" "${SECRETS_RUNTIME}/mcsmanager/web/User"
migrate_dir "/opt/data/mcsmanager/web/data/RemoteServiceConfig" "${SECRETS_RUNTIME}/mcsmanager/web/RemoteServiceConfig"

find "$SECRETS_RUNTIME" -type d -exec chmod 700 {} +
find "$SECRETS_RUNTIME" -type f -exec chmod 600 {} +

if [[ "$EXPORT_AFTER" -eq 1 ]]; then
  bash "${SCRIPT_DIR}/sync-secrets-repo.sh" export
fi

log "secret migration completed"
