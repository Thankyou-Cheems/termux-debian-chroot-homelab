#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

usage() {
  cat <<'EOF'
Usage:
  install-cron.sh [--template <cron-file>]

Default template:
  /opt/ops/deploy/cron/ops-backup.cron
EOF
}

TEMPLATE_FILE="${OPS_REPO}/deploy/cron/ops-backup.cron"
TARGET_FILE="/etc/cron.d/ops-backup"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --template)
      TEMPLATE_FILE="${2:-}"
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

[[ -f "$TEMPLATE_FILE" ]] || die "cron template not found: ${TEMPLATE_FILE}"

if ! command -v cron >/dev/null 2>&1 && ! command -v crond >/dev/null 2>&1; then
  die "cron is not installed. install it first (apt-get install -y cron)"
fi

install -m 0644 "$TEMPLATE_FILE" "$TARGET_FILE"
log "cron file installed: ${TARGET_FILE}"

if command -v systemctl >/dev/null 2>&1; then
  systemctl enable cron >/dev/null 2>&1 || true
  systemctl restart cron >/dev/null 2>&1 || true
  log "attempted to enable/restart cron via systemctl"
fi

log "cron setup completed"

