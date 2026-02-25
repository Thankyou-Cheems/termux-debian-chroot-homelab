#!/usr/bin/env bash
set -euo pipefail

OPS_ROOT="${OPS_ROOT:-/opt}"
OPS_REPO="${OPS_REPO:-${OPS_ROOT}/ops}"
APP_ROOT="${APP_ROOT:-${OPS_ROOT}/apps}"
DATA_ROOT="${DATA_ROOT:-${OPS_ROOT}/data}"
LOG_ROOT="${LOG_ROOT:-${OPS_ROOT}/logs}"
BACKUP_ROOT="${BACKUP_ROOT:-${OPS_ROOT}/backup}"
SECRETS_ROOT="${SECRETS_ROOT:-${OPS_ROOT}/secrets}"

timestamp() {
  date "+%Y%m%d-%H%M%S"
}

log() {
  printf '[%s] %s\n' "$(date '+%F %T')" "$*"
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing command: $1"
}

ensure_base_dirs() {
  mkdir -p \
    "$APP_ROOT" \
    "$DATA_ROOT" \
    "$LOG_ROOT" \
    "$BACKUP_ROOT/git-bundles" \
    "$BACKUP_ROOT/data-snapshots" \
    "$SECRETS_ROOT"
}

