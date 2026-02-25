#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

usage() {
  cat <<'EOF'
Usage:
  prune-backup-history.sh [--repo <repo>] --path <backup-artifacts/runs/...> [--path <...>]

Examples:
  bash /opt/ops/scripts/prune-backup-history.sh \
    --repo /opt/ops \
    --path backup-artifacts/runs/20260225-120531

Notes:
  1. This script rewrites Git history to drop old backup run paths.
  2. Use on private repositories only.
  3. After rewrite, push with --force-with-lease.
EOF
}

TARGET_REPO="${OPS_REPO:-/opt/ops}"
declare -a DROP_PATHS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      TARGET_REPO="${2:-}"
      shift 2
      ;;
    --path)
      DROP_PATHS+=("${2:-}")
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

[[ -d "${TARGET_REPO}/.git" ]] || die "git repo not found: ${TARGET_REPO}"
[[ "${#DROP_PATHS[@]}" -gt 0 ]] || die "at least one --path is required"

declare -A SEEN=()
declare -a UNIQUE_PATHS=()

for RAW_PATH in "${DROP_PATHS[@]}"; do
  CLEAN_PATH="${RAW_PATH#./}"
  [[ -n "$CLEAN_PATH" ]] || continue
  [[ "$CLEAN_PATH" == backup-artifacts/runs/* ]] || die "path not allowed: ${CLEAN_PATH}"
  if [[ -z "${SEEN[$CLEAN_PATH]+x}" ]]; then
    UNIQUE_PATHS+=("$CLEAN_PATH")
    SEEN["$CLEAN_PATH"]=1
  fi
done

[[ "${#UNIQUE_PATHS[@]}" -gt 0 ]] || die "no valid paths to prune"

if [[ -n "$(git -C "$TARGET_REPO" status --porcelain --untracked-files=no)" ]]; then
  die "repo has tracked changes, commit first: ${TARGET_REPO}"
fi

if command -v git-filter-repo >/dev/null 2>&1; then
  PRUNE_CMD=(git -C "$TARGET_REPO" filter-repo --force --invert-path)
  for PRUNE_PATH in "${UNIQUE_PATHS[@]}"; do
    PRUNE_CMD+=(--path "$PRUNE_PATH")
  done
  "${PRUNE_CMD[@]}"
  log "history rewritten via git-filter-repo (${#UNIQUE_PATHS[@]} path(s))"
else
  INDEX_FILTER_ARGS=(git rm -r --cached --ignore-unmatch)
  for PRUNE_PATH in "${UNIQUE_PATHS[@]}"; do
    INDEX_FILTER_ARGS+=("$PRUNE_PATH")
  done
  printf -v INDEX_FILTER_CMD '%q ' "${INDEX_FILTER_ARGS[@]}"
  FILTER_BRANCH_SQUELCH_WARNING=1 git -C "$TARGET_REPO" filter-branch \
    --force \
    --index-filter "$INDEX_FILTER_CMD" \
    --prune-empty \
    --tag-name-filter cat \
    -- --all
  rm -rf "${TARGET_REPO}/.git/refs/original"
  log "history rewritten via git filter-branch (${#UNIQUE_PATHS[@]} path(s))"
fi

git -C "$TARGET_REPO" reflog expire --expire=now --all
git -C "$TARGET_REPO" gc --prune=now --aggressive
log "git gc completed; force-push rewritten refs if remote exists"
