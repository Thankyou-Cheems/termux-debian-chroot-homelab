#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

usage() {
  cat <<'EOF'
Usage:
  deploy.sh --service <name> [--ref <git-ref>] [--keep-releases <n>]

Examples:
  bash /opt/ops/scripts/deploy.sh --service api --ref main
  bash /opt/ops/scripts/deploy.sh --service worker --ref prod-20260224-0900
EOF
}

SERVICE=""
REF="HEAD"
KEEP_RELEASES=5

while [[ $# -gt 0 ]]; do
  case "$1" in
    --service|-s)
      SERVICE="${2:-}"
      shift 2
      ;;
    --ref|-r)
      REF="${2:-}"
      shift 2
      ;;
    --keep-releases)
      KEEP_RELEASES="${2:-}"
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

[[ -n "$SERVICE" ]] || {
  usage
  die "--service is required"
}
[[ "$KEEP_RELEASES" =~ ^[0-9]+$ ]] || die "--keep-releases must be a non-negative integer"

require_cmd git
require_cmd tar
ensure_base_dirs

[[ -d "${OPS_REPO}/.git" ]] || die "ops repo not found: ${OPS_REPO}"
git -C "$OPS_REPO" rev-parse --verify "${REF}^{commit}" >/dev/null 2>&1 || die "invalid git ref: ${REF}"
git -C "$OPS_REPO" cat-file -e "${REF}:services/${SERVICE}" 2>/dev/null || die "service path not found in ref ${REF}: services/${SERVICE}"

RELEASE_ROOT="${APP_ROOT}/${SERVICE}/releases"
RELEASE_DIR="${RELEASE_ROOT}/$(timestamp)"
mkdir -p "$RELEASE_DIR"

log "deploying service=${SERVICE} ref=${REF} to ${RELEASE_DIR}"
git -C "$OPS_REPO" archive "$REF" "services/${SERVICE}" | tar -x -C "$RELEASE_DIR"

[[ -d "${RELEASE_DIR}/services/${SERVICE}" ]] || die "unexpected archive layout for service ${SERVICE}"
shopt -s dotglob nullglob
mv "${RELEASE_DIR}/services/${SERVICE}"/* "${RELEASE_DIR}/"
shopt -u dotglob nullglob
rm -rf "${RELEASE_DIR}/services"

echo "$REF" > "${RELEASE_DIR}/.deploy_ref"
git -C "$OPS_REPO" rev-parse "$REF" > "${RELEASE_DIR}/.deploy_commit"
date -u +"%Y-%m-%dT%H:%M:%SZ" > "${RELEASE_DIR}/.deploy_time_utc"

ln -sfn "$RELEASE_DIR" "${APP_ROOT}/${SERVICE}/current"
log "updated current -> ${RELEASE_DIR}"

if [[ "$KEEP_RELEASES" -gt 0 ]]; then
  mapfile -t RELEASES < <(find "$RELEASE_ROOT" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' | sort -nr | awk '{print $2}')
  if [[ "${#RELEASES[@]}" -gt "$KEEP_RELEASES" ]]; then
    for OLD_RELEASE in "${RELEASES[@]:$KEEP_RELEASES}"; do
      rm -rf "$OLD_RELEASE"
      log "removed old release: $OLD_RELEASE"
    done
  fi
fi

log "deploy finished for service=${SERVICE}"

