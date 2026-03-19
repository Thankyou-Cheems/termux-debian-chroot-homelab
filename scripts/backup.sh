#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

usage() {
  cat <<'EOF'
Usage:
  backup.sh [--retention-days <days>] [--repo-artifacts-keep <count>] [--skip-git] [--skip-data] [--keep-temp-dirs] [--skip-secrets-sync] [--skip-repo-artifacts-sync] [--skip-repo-backup-commit] [--skip-repo-history-prune]

Examples:
  bash /opt/ops/scripts/backup.sh
  bash /opt/ops/scripts/backup.sh --retention-days 30
  bash /opt/ops/scripts/backup.sh --skip-data
EOF
}

RETENTION_DAYS="${RETENTION_DAYS:-14}"
REPO_ARTIFACTS_KEEP="${REPO_ARTIFACTS_KEEP:-3}"
SKIP_GIT=0
SKIP_DATA=0
KEEP_TEMP_DIRS=0
SKIP_SECRETS_SYNC=0
SKIP_REPO_ARTIFACTS_SYNC=0
SKIP_REPO_BACKUP_COMMIT=0
SKIP_REPO_HISTORY_PRUNE=0
BUNDLE_FILE=""
DATA_FILE=""
ARTIFACTS_UPDATED=0
declare -a DROPPED_REPO_RUN_PATHS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --retention-days)
      RETENTION_DAYS="${2:-}"
      shift 2
      ;;
    --repo-artifacts-keep)
      REPO_ARTIFACTS_KEEP="${2:-}"
      shift 2
      ;;
    --skip-git)
      SKIP_GIT=1
      shift
      ;;
    --skip-data)
      SKIP_DATA=1
      shift
      ;;
    --keep-temp-dirs)
      KEEP_TEMP_DIRS=1
      shift
      ;;
    --skip-secrets-sync)
      SKIP_SECRETS_SYNC=1
      shift
      ;;
    --skip-repo-artifacts-sync)
      SKIP_REPO_ARTIFACTS_SYNC=1
      shift
      ;;
    --skip-repo-backup-commit)
      SKIP_REPO_BACKUP_COMMIT=1
      shift
      ;;
    --skip-repo-history-prune)
      SKIP_REPO_HISTORY_PRUNE=1
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

[[ "$RETENTION_DAYS" =~ ^[0-9]+$ ]] || die "--retention-days must be a non-negative integer"
[[ "$REPO_ARTIFACTS_KEEP" =~ ^[0-9]+$ ]] || die "--repo-artifacts-keep must be a positive integer"
[[ "$REPO_ARTIFACTS_KEEP" -ge 1 ]] || die "--repo-artifacts-keep must be at least 1"

ensure_base_dirs
require_cmd tar
require_cmd git

if [[ "$SKIP_SECRETS_SYNC" -eq 0 ]]; then
  SECRETS_SYNC_SCRIPT="${SCRIPT_DIR}/sync-secrets-repo.sh"
  [[ -x "$SECRETS_SYNC_SCRIPT" ]] || die "missing executable secrets sync helper: ${SECRETS_SYNC_SCRIPT}"
  bash "$SECRETS_SYNC_SCRIPT" export
  if ! git -C "$OPS_REPO" diff --quiet -- secrets/live; then
    log "secrets mirror updated in working tree: ${OPS_REPO}/secrets/live (commit if you need it in git bundle)"
  fi
fi

STAMP="$(timestamp)"

if [[ "$SKIP_GIT" -eq 0 ]]; then
  [[ -d "${OPS_REPO}/.git" ]] || die "ops repo not found: ${OPS_REPO}"
  git -C "$OPS_REPO" rev-parse --verify HEAD >/dev/null 2>&1 || die "ops repo has no commits"

  BUNDLE_FILE="${BACKUP_ROOT}/git-bundles/ops-${STAMP}.bundle"
  git -C "$OPS_REPO" bundle create "$BUNDLE_FILE" --all --tags
  log "git bundle created: ${BUNDLE_FILE}"
fi

if [[ "$SKIP_DATA" -eq 0 ]]; then
  DATA_FILE="${BACKUP_ROOT}/data-snapshots/data-${STAMP}.tar.gz"
  tar \
    -C "$OPS_ROOT" \
    --exclude='data/syncthing/sync' \
    --exclude='data/aria2/data' \
    --exclude='data/transmission/data' \
    --exclude='data/transmission/incomplete' \
    --exclude='data/filebrowser/root' \
    -czf "$DATA_FILE" \
    data
  log "data snapshot created: ${DATA_FILE} (excluded: /opt/data/syncthing/sync, /opt/data/aria2/data, /opt/data/transmission/data, /opt/data/transmission/incomplete, /opt/data/filebrowser/root)"
fi

if [[ "$SKIP_REPO_ARTIFACTS_SYNC" -eq 0 ]]; then
  REPO_ARTIFACTS_ROOT="${OPS_REPO}/backup-artifacts"
  REPO_ARTIFACTS_RUNS_DIR="${REPO_ARTIFACTS_ROOT}/runs"
  REPO_ARTIFACTS_LATEST_DIR="${REPO_ARTIFACTS_ROOT}/latest"
  REPO_ARTIFACTS_RUN_DIR="${REPO_ARTIFACTS_RUNS_DIR}/${STAMP}"
  mkdir -p "$REPO_ARTIFACTS_RUNS_DIR" "$REPO_ARTIFACTS_LATEST_DIR"

  if [[ -n "$BUNDLE_FILE" && -f "$BUNDLE_FILE" ]]; then
    mkdir -p "$REPO_ARTIFACTS_RUN_DIR"
    cp -f "$BUNDLE_FILE" "${REPO_ARTIFACTS_RUN_DIR}/ops.bundle"
    ARTIFACTS_UPDATED=1
  fi
  if [[ -n "$DATA_FILE" && -f "$DATA_FILE" ]]; then
    mkdir -p "$REPO_ARTIFACTS_RUN_DIR"
    cp -f "$DATA_FILE" "${REPO_ARTIFACTS_RUN_DIR}/data.tar.gz"
    ARTIFACTS_UPDATED=1
  fi

  if [[ "$ARTIFACTS_UPDATED" -eq 1 ]]; then
    {
      echo "backup_time_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
      [[ -n "$BUNDLE_FILE" ]] && echo "bundle_source=${BUNDLE_FILE}" || true
      [[ -n "$DATA_FILE" ]] && echo "snapshot_source=${DATA_FILE}" || true
      if command -v sha256sum >/dev/null 2>&1; then
        [[ -f "${REPO_ARTIFACTS_RUN_DIR}/ops.bundle" ]] && \
          echo "bundle_sha256=$(sha256sum "${REPO_ARTIFACTS_RUN_DIR}/ops.bundle" | awk '{print $1}')" || true
        [[ -f "${REPO_ARTIFACTS_RUN_DIR}/data.tar.gz" ]] && \
          echo "snapshot_sha256=$(sha256sum "${REPO_ARTIFACTS_RUN_DIR}/data.tar.gz" | awk '{print $1}')" || true
      fi
    } > "${REPO_ARTIFACTS_RUN_DIR}/backup-meta.env"

    ln -sfn "../runs/${STAMP}/backup-meta.env" "${REPO_ARTIFACTS_LATEST_DIR}/backup-meta.env"
    if [[ -f "${REPO_ARTIFACTS_RUN_DIR}/ops.bundle" ]]; then
      ln -sfn "../runs/${STAMP}/ops.bundle" "${REPO_ARTIFACTS_LATEST_DIR}/ops-latest.bundle"
    else
      rm -f "${REPO_ARTIFACTS_LATEST_DIR}/ops-latest.bundle"
    fi
    if [[ -f "${REPO_ARTIFACTS_RUN_DIR}/data.tar.gz" ]]; then
      ln -sfn "../runs/${STAMP}/data.tar.gz" "${REPO_ARTIFACTS_LATEST_DIR}/data-latest.tar.gz"
    else
      rm -f "${REPO_ARTIFACTS_LATEST_DIR}/data-latest.tar.gz"
    fi

    mapfile -t REPO_RUN_STAMPS < <(
      find "$REPO_ARTIFACTS_RUNS_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort -r
    )
    if [[ "${#REPO_RUN_STAMPS[@]}" -gt "$REPO_ARTIFACTS_KEEP" ]]; then
      for OLD_STAMP in "${REPO_RUN_STAMPS[@]:$REPO_ARTIFACTS_KEEP}"; do
        rm -rf "${REPO_ARTIFACTS_RUNS_DIR}/${OLD_STAMP}"
        DROPPED_REPO_RUN_PATHS+=("backup-artifacts/runs/${OLD_STAMP}")
      done
    fi

    log "repo backup artifacts synced: ${REPO_ARTIFACTS_ROOT} (kept ${REPO_ARTIFACTS_KEEP} runs)"
  else
    log "repo backup artifacts sync skipped (no new bundle/snapshot in this run)"
  fi
fi

if [[ "$SKIP_REPO_BACKUP_COMMIT" -eq 0 ]]; then
  git -C "$OPS_REPO" add -A -- backup-artifacts secrets/live
  if ! git -C "$OPS_REPO" diff --cached --quiet -- backup-artifacts secrets/live; then
    git -C "$OPS_REPO" commit -m "chore(backup): refresh tracked backup artifacts ${STAMP}" -- backup-artifacts secrets/live
    log "repo backup commit created for backup-artifacts + secrets/live"
  fi
fi

if [[ "$SKIP_REPO_HISTORY_PRUNE" -eq 0 && "$SKIP_REPO_BACKUP_COMMIT" -eq 0 && "${#DROPPED_REPO_RUN_PATHS[@]}" -gt 0 ]]; then
  PRUNE_HISTORY_SCRIPT="${SCRIPT_DIR}/prune-backup-history.sh"
  [[ -x "$PRUNE_HISTORY_SCRIPT" ]] || die "missing executable repo history prune helper: ${PRUNE_HISTORY_SCRIPT}"

  if [[ -n "$(git -C "$OPS_REPO" status --porcelain --untracked-files=no)" ]]; then
    log "repo history prune skipped (tracked worktree not clean)"
  else
    PRUNE_ARGS=(--repo "$OPS_REPO")
    for OLD_PATH in "${DROPPED_REPO_RUN_PATHS[@]}"; do
      PRUNE_ARGS+=(--path "$OLD_PATH")
    done
    bash "$PRUNE_HISTORY_SCRIPT" "${PRUNE_ARGS[@]}"
    log "repo history prune completed for removed backup runs: ${#DROPPED_REPO_RUN_PATHS[@]}"
  fi
fi

if [[ "$RETENTION_DAYS" -gt 0 ]]; then
  find "${BACKUP_ROOT}/git-bundles" -type f -name '*.bundle' -mtime "+${RETENTION_DAYS}" -delete
  find "${BACKUP_ROOT}/data-snapshots" -type f -name '*.tar.gz' -mtime "+${RETENTION_DAYS}" -delete
  if [[ "$KEEP_TEMP_DIRS" -eq 0 ]]; then
    find "${BACKUP_ROOT}/data-snapshots" -mindepth 1 -maxdepth 1 -type d -mtime "+${RETENTION_DAYS}" -delete
  fi
  log "cleanup done for backups older than ${RETENTION_DAYS} days"
fi

log "backup completed"
