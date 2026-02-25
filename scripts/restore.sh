#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

usage() {
  cat <<'EOF'
Usage:
  restore.sh [--bundle <file>] [--data <file>] [--ref <git-ref>] [--force-data]

Examples:
  bash /opt/ops/scripts/restore.sh --bundle /opt/backup/git-bundles/ops-20260224-140000.bundle
  bash /opt/ops/scripts/restore.sh --data /opt/backup/data-snapshots/data-20260224-140000.tar.gz --force-data
  bash /opt/ops/scripts/restore.sh --bundle <bundle> --data <snapshot> --ref main --force-data
EOF
}

BUNDLE_FILE=""
DATA_FILE=""
REF=""
FORCE_DATA=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bundle)
      BUNDLE_FILE="${2:-}"
      shift 2
      ;;
    --data)
      DATA_FILE="${2:-}"
      shift 2
      ;;
    --ref)
      REF="${2:-}"
      shift 2
      ;;
    --force-data)
      FORCE_DATA=1
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

[[ -n "$BUNDLE_FILE" || -n "$DATA_FILE" ]] || {
  usage
  die "at least one of --bundle or --data is required"
}

ensure_base_dirs

if [[ -n "$BUNDLE_FILE" ]]; then
  require_cmd git
  [[ -f "$BUNDLE_FILE" ]] || die "bundle file not found: ${BUNDLE_FILE}"

  if [[ ! -d "${OPS_REPO}/.git" ]]; then
    if [[ -d "${OPS_REPO}" && -n "$(ls -A "${OPS_REPO}" 2>/dev/null)" ]]; then
      die "target repo path exists and is not empty: ${OPS_REPO}"
    fi
    rm -rf "${OPS_REPO}"
    git clone "$BUNDLE_FILE" "$OPS_REPO"
    log "cloned ops repo from bundle: ${BUNDLE_FILE}"
  else
    git -C "$OPS_REPO" fetch "$BUNDLE_FILE" 'refs/heads/*:refs/heads/*' 'refs/tags/*:refs/tags/*'
    log "fetched refs from bundle into existing repo: ${BUNDLE_FILE}"
  fi

  if [[ -n "$REF" ]]; then
    git -C "$OPS_REPO" rev-parse --verify "${REF}^{commit}" >/dev/null 2>&1 || die "invalid ref after restore: ${REF}"
    git -C "$OPS_REPO" checkout "$REF"
    log "checked out ref: ${REF}"
  fi
fi

if [[ -n "$DATA_FILE" ]]; then
  require_cmd tar
  [[ -f "$DATA_FILE" ]] || die "data snapshot not found: ${DATA_FILE}"

  if find "$DATA_ROOT" -mindepth 1 -maxdepth 1 | grep -q .; then
    if [[ "$FORCE_DATA" -ne 1 ]]; then
      die "${DATA_ROOT} is not empty, use --force-data to continue"
    fi
    BACKUP_BEFORE_RESTORE="${OPS_ROOT}/data.pre-restore-$(timestamp)"
    mv "$DATA_ROOT" "$BACKUP_BEFORE_RESTORE"
    mkdir -p "$DATA_ROOT"
    log "existing data moved to: ${BACKUP_BEFORE_RESTORE}"
  fi

  tar -C "$OPS_ROOT" -xzf "$DATA_FILE"
  log "data restored from snapshot: ${DATA_FILE}"
fi

log "restore completed"

