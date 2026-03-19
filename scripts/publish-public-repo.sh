#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  publish-public-repo.sh [--source <ops_repo>] [--remote <git_url>] [--branch <name>] [--workdir <path>] [--message <msg>]

Examples:
  bash /opt/ops/scripts/publish-public-repo.sh
  bash /opt/ops/scripts/publish-public-repo.sh --remote https://github.com/<user>/<repo>.git

Description:
  1) Export a sanitized public snapshot to a temporary directory
  2) Clone or reuse a temporary public git worktree
  3) Replace worktree contents with the sanitized export while preserving .git
  4) Commit and push to the public remote
EOF
}

SOURCE_REPO="/opt/ops"
REMOTE_URL="https://github.com/<GITHUB_USER>/termux-debian-chroot-homelab.git"
BRANCH="main"
WORKDIR="/tmp/ops-public-publish-repo"
EXPORT_DIR="/tmp/ops-public-publish-export"
COMMIT_MESSAGE="feat(public): sync sanitized ops architecture and download stack"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)
      SOURCE_REPO="${2:-}"
      shift 2
      ;;
    --remote)
      REMOTE_URL="${2:-}"
      shift 2
      ;;
    --branch)
      BRANCH="${2:-}"
      shift 2
      ;;
    --workdir)
      WORKDIR="${2:-}"
      EXPORT_DIR="${WORKDIR}-export"
      shift 2
      ;;
    --message)
      COMMIT_MESSAGE="${2:-}"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

rm -rf "$EXPORT_DIR" "$WORKDIR"

bash /opt/ops/scripts/export-public-repo.sh \
  --source "$SOURCE_REPO" \
  --output "$EXPORT_DIR" \
  --force

git clone --branch "$BRANCH" "$REMOTE_URL" "$WORKDIR"

python3 - <<'PY' "$EXPORT_DIR" "$WORKDIR"
import os
import shutil
import sys

src, dst = sys.argv[1], sys.argv[2]

for name in os.listdir(dst):
    if name == ".git":
        continue
    path = os.path.join(dst, name)
    if os.path.isdir(path) and not os.path.islink(path):
        shutil.rmtree(path)
    else:
        os.remove(path)

for name in os.listdir(src):
    s = os.path.join(src, name)
    d = os.path.join(dst, name)
    if os.path.isdir(s) and not os.path.islink(s):
        shutil.copytree(s, d, symlinks=True)
    else:
        shutil.copy2(s, d, follow_symlinks=False)
PY

cd "$WORKDIR"
git config user.name "<GITHUB_USER>"
git config user.email "78412531+<GITHUB_USER>@users.noreply.github.com"

if [[ -n "$(git status --short)" ]]; then
  git add -A
  git commit -m "$COMMIT_MESSAGE"
  git push origin "$BRANCH"
  echo "public repo published: $REMOTE_URL ($BRANCH)"
else
  echo "public repo already up-to-date: $REMOTE_URL ($BRANCH)"
fi
