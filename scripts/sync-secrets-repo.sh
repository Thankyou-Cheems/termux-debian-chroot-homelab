#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

usage() {
  cat <<'EOF'
Usage:
  sync-secrets-repo.sh <export|import>

Commands:
  export   Copy runtime secrets from /opt/secrets into /opt/ops/secrets/live
  import   Copy tracked secrets from /opt/ops/secrets/live into /opt/secrets
EOF
}

MODE="${1:-}"
[[ -n "$MODE" ]] || {
  usage
  exit 1
}

SECRETS_RUNTIME="${SECRETS_ROOT:-${OPS_ROOT}/secrets}"
SECRETS_REPO="${OPS_REPO}/secrets/live"

copy_tree() {
  local src="$1"
  local dst="$2"
  mkdir -p "$dst"
  rm -rf "${dst:?}"/*
  if [[ -d "$src" ]] && [[ -n "$(find "$src" -mindepth 1 -maxdepth 1 2>/dev/null)" ]]; then
    tar -C "$src" -cf - . | tar -C "$dst" -xf -
  fi
}

harden_permissions() {
  local root="$1"
  [[ -d "$root" ]] || return 0
  chmod 700 "$root"
  find "$root" -type d -exec chmod 700 {} +
  find "$root" -type f -exec chmod 600 {} +
}

case "$MODE" in
  export)
    [[ -d "$SECRETS_RUNTIME" ]] || die "runtime secrets path not found: ${SECRETS_RUNTIME}"
    mkdir -p "${OPS_REPO}/secrets"
    copy_tree "$SECRETS_RUNTIME" "$SECRETS_REPO"
    harden_permissions "$SECRETS_REPO"
    log "exported runtime secrets to repo: ${SECRETS_REPO}"
    ;;
  import)
    [[ -d "$SECRETS_REPO" ]] || die "tracked secrets path not found: ${SECRETS_REPO}"
    mkdir -p "$SECRETS_RUNTIME"
    copy_tree "$SECRETS_REPO" "$SECRETS_RUNTIME"
    harden_permissions "$SECRETS_RUNTIME"
    log "imported tracked secrets to runtime: ${SECRETS_RUNTIME}"
    ;;
  *)
    usage
    die "unknown mode: ${MODE}"
    ;;
esac
