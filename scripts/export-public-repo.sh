#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./lib.sh
source "${SCRIPT_DIR}/lib.sh"

usage() {
  cat <<'EOF'
Usage:
  export-public-repo.sh [--source <ops_repo>] [--output <export_dir>] [--force] [--init-git]

Examples:
  bash /opt/ops/scripts/export-public-repo.sh
  bash /opt/ops/scripts/export-public-repo.sh --output /tmp/ops-public-export --force --init-git

Description:
  Build a public-safe repository snapshot from a private /opt/ops repo by:
  1) allowlist-copying docs/scripts/templates only
  2) removing known sensitive runtime payload paths
  3) applying text redaction placeholders

Important:
  This script produces a sanitized export directory.
  Do not point --output at an existing public Git worktree and use --force,
  because that will remove the worktree contents including .git metadata.
  Use publish-public-repo.sh for the full "export + sync + commit + push" flow.
EOF
}

SOURCE_REPO="/opt/ops"
OUTPUT_DIR="/tmp/ops-public-export"
FORCE_OVERWRITE=0
INIT_GIT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)
      SOURCE_REPO="${2:-}"
      shift 2
      ;;
    --output)
      OUTPUT_DIR="${2:-}"
      shift 2
      ;;
    --force)
      FORCE_OVERWRITE=1
      shift
      ;;
    --init-git)
      INIT_GIT=1
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

[[ -d "${SOURCE_REPO}/.git" ]] || die "source is not a git repository: ${SOURCE_REPO}"
require_cmd find
require_cmd grep
require_cmd sed

SOURCE_REMOTE_URL="$(git -C "$SOURCE_REPO" config --get remote.origin.url || true)"
SOURCE_GITHUB_USER=""
SOURCE_REPO_NAME=""
if [[ "$SOURCE_REMOTE_URL" =~ github\.com[:/]([^/]+)/([^/.]+)(\.git)?$ ]]; then
  SOURCE_GITHUB_USER="${BASH_REMATCH[1]}"
  SOURCE_REPO_NAME="${BASH_REMATCH[2]}"
fi
REDACT_GITHUB_USER="${REDACT_GITHUB_USER:-$SOURCE_GITHUB_USER}"
REDACT_REPO_NAME="${REDACT_REPO_NAME:-$SOURCE_REPO_NAME}"

if [[ -d "${OUTPUT_DIR}/.git" && "$FORCE_OVERWRITE" -eq 1 ]]; then
  die "refusing to --force overwrite an existing git worktree: ${OUTPUT_DIR} (use publish-public-repo.sh instead)"
fi

if [[ -e "$OUTPUT_DIR" ]]; then
  if [[ "$FORCE_OVERWRITE" -eq 1 ]]; then
    rm -rf "$OUTPUT_DIR"
  else
    die "output already exists: ${OUTPUT_DIR} (use --force to overwrite)"
  fi
fi

TMP_DIR="$(mktemp -d /tmp/ops-public-export.XXXXXX)"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# Allowlist-copy only reproducible control-plane content (tracked files only).
while IFS= read -r rel_path; do
  case "$rel_path" in
    README.md|docs/*|deploy/*|scripts/*|services/portal/*|env/*|host/*|backup-artifacts/README.md|secrets/README.md)
      mkdir -p "${TMP_DIR}/$(dirname "$rel_path")"
      cp -a "${SOURCE_REPO}/${rel_path}" "${TMP_DIR}/${rel_path}"
      ;;
    *)
      ;;
  esac
done < <(git -C "$SOURCE_REPO" ls-files)

# Hard-delete sensitive or high-noise payload paths if copied in by future changes.
rm -rf \
  "${TMP_DIR}/secrets/live" \
  "${TMP_DIR}/backup-artifacts/runs" \
  "${TMP_DIR}/backup-artifacts/latest"

# Export Magisk EasyTier config as template only.
if [[ -f "${SOURCE_REPO}/host/magisk/easytier/config/config.toml" ]]; then
  mkdir -p "${TMP_DIR}/host/magisk/easytier/config"
  cp -f \
    "${SOURCE_REPO}/host/magisk/easytier/config/config.toml" \
    "${TMP_DIR}/host/magisk/easytier/config/config.toml.example"
fi
rm -f "${TMP_DIR}/host/magisk/easytier/config/config.toml"
rm -f "${TMP_DIR}/host/magisk/easytier/config/command_args"

sanitize_easytier_template() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  sed -E -i \
    -e 's|^hostname[[:space:]]*=.*$|hostname = "<HOSTNAME>"|' \
    -e 's|^instance_name[[:space:]]*=.*$|instance_name = "<INSTANCE_NAME>"|' \
    -e 's|^instance_id[[:space:]]*=.*$|instance_id = "<INSTANCE_ID>"|' \
    -e 's|^ipv4[[:space:]]*=.*$|ipv4 = "<HOST_IP>/24"|' \
    -e 's|^network_name[[:space:]]*=.*$|network_name = "<NETWORK_NAME>"|' \
    -e 's|^network_secret[[:space:]]*=.*$|network_secret = "<NETWORK_SECRET>"|' \
    -e 's|^uri[[:space:]]*=.*$|uri = "tcp://<PEER_IP>:11010"|' \
    -e 's|^dev_name[[:space:]]*=.*$|dev_name = "<EASYTIER_DEV_NAME>"|' \
    "$file"
}

escape_sed_literal() {
  printf '%s' "$1" | sed -e 's/[\/&]/\\&/g'
}

sanitize_text_file() {
  local file="$1"
  sed -E -i \
    -e 's|10\.[0-9]+\.[0-9]+\.[0-9]+|<HOST_IP>|g' \
    -e 's|192\.168\.[0-9]+\.[0-9]+|<HOST_IP>|g' \
    -e 's#172\.(1[6-9]|2[0-9]|3[0-1])\.[0-9]+\.[0-9]+#<HOST_IP>#g' \
    -e 's#100\.(6[4-9]|[7-9][0-9]|1[0-1][0-9]|12[0-7])\.[0-9]+\.[0-9]+#<HOST_IP>#g' \
    -e 's|u0_a[0-9]+|<TERMUX_USER>|g' \
    -e 's|<GITHUB_USER>|<GITHUB_USER>|g' \
    -e 's|<DEPLOYMENT_REPO>|<DEPLOYMENT_REPO>|g' \
    -e 's|<CHROOT_DIR>|<CHROOT_DIR>|g' \
    -e 's|/data/data/com\.termux/files/home|<TERMUX_HOME>|g' \
    -e 's|[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}|<UUID>|g' \
    "$file"

  if [[ -n "$REDACT_GITHUB_USER" ]]; then
    sed -i "s|$(escape_sed_literal "$REDACT_GITHUB_USER")|<GITHUB_USER>|g" "$file"
  fi
  if [[ -n "$REDACT_REPO_NAME" ]]; then
    sed -i "s|$(escape_sed_literal "$REDACT_REPO_NAME")|<DEPLOYMENT_REPO>|g" "$file"
  fi

  # Redact common key-value secret lines in config-like files.
  sed -E -i \
    -e 's#^([[:space:]]*(network_secret|password|passwd|passphrase|token|secret|api[_-]?key|client_secret|access_key|rpc-secret)[[:space:]]*[:=][[:space:]]*).*$#\1"<REDACTED>"#I' \
    "$file"
}

while IFS= read -r -d '' path; do
  if grep -Iq . "$path"; then
    sanitize_text_file "$path"
  fi
done < <(find "$TMP_DIR" -type f -print0)

sanitize_easytier_template "${TMP_DIR}/host/magisk/easytier/config/config.toml.example"

run_leak_sentinel() {
  local root="$1"
  local hits

  hits="$(grep -RInE --exclude-dir=.git \
    'ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|gho_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{20,}|xox[baprs]-[0-9A-Za-z-]{10,}|-----BEGIN (RSA|OPENSSH|EC|DSA|PGP|PRIVATE) KEY-----|u0_a[0-9]+|<CHROOT_DIR>|/data/data/com\.termux/files/home|<GITHUB_USER>|<DEPLOYMENT_REPO>' \
    "$root" || true)"
  if [[ -n "$hits" ]]; then
    printf '%s\n' "$hits" >&2
    die "public export leak sentinel hit sensitive markers"
  fi

  if [[ -n "$REDACT_GITHUB_USER" ]]; then
    hits="$(grep -RInF --exclude-dir=.git "$REDACT_GITHUB_USER" "$root" || true)"
    if [[ -n "$hits" ]]; then
      printf '%s\n' "$hits" >&2
      die "public export leak sentinel hit source github user marker"
    fi
  fi

  if [[ -n "$REDACT_REPO_NAME" ]]; then
    hits="$(grep -RInF --exclude-dir=.git "$REDACT_REPO_NAME" "$root" || true)"
    if [[ -n "$hits" ]]; then
      printf '%s\n' "$hits" >&2
      die "public export leak sentinel hit source repo marker"
    fi
  fi

  hits="$(grep -RInE --exclude-dir=.git \
    '\b(10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}|192\.168\.[0-9]{1,3}\.[0-9]{1,3}|172\.(1[6-9]|2[0-9]|3[0-1])\.[0-9]{1,3}\.[0-9]{1,3}|100\.(6[4-9]|[7-9][0-9]|1[0-1][0-9]|12[0-7])\.[0-9]{1,3}\.[0-9]{1,3})\b' \
    "$root" || true)"
  if [[ -n "$hits" ]]; then
    printf '%s\n' "$hits" >&2
    die "public export leak sentinel hit private-range IP literals"
  fi

  hits="$(grep -RInE --exclude-dir=.git \
    '^[[:space:]]*(network_secret|password|passwd|passphrase|token|secret|api[_-]?key|client_secret|access_key|rpc-secret)[[:space:]]*[:=][[:space:]]*\"[^\"]+\"[[:space:]]*$' \
    "$root" | grep -vE '(<REDACTED>|<NETWORK_SECRET>)' || true)"
  if [[ -n "$hits" ]]; then
    printf '%s\n' "$hits" >&2
    die "public export leak sentinel hit raw key-value secrets"
  fi
}

run_leak_sentinel "$TMP_DIR"

cat > "${TMP_DIR}/.gitignore" <<'EOF'
# Public repo safety rail
secrets/live/
backup-artifacts/latest/
backup-artifacts/runs/

# Local-only env overrides
*.local
*.env
EOF

cat > "${TMP_DIR}/PUBLIC_EXPORT.md" <<'EOF'
# Public Export Notes

This repository is generated from a private `/opt/ops` control-plane repo.

Sanitization policy:

1. Runtime secrets are excluded (`secrets/live`).
2. Binary backup payloads are excluded (`backup-artifacts/latest`, `backup-artifacts/runs`).
3. Host-specific values are replaced with placeholders:
   - `<HOST_IP>`
   - `<TERMUX_USER>`
   - `<TERMUX_HOME>`
   - `<CHROOT_DIR>`
   - `<GITHUB_USER>`
   - `<DEPLOYMENT_REPO>`
   - `<NETWORK_SECRET>`
   - `<PEER_IP>`
4. Build fails if leak sentinel detects sensitive markers.

Regenerate:

1. Temporary export only: `bash /opt/ops/scripts/export-public-repo.sh --force --output /tmp/ops-public-export`
2. Full publish flow: `bash /opt/ops/scripts/publish-public-repo.sh`
EOF

mv "$TMP_DIR" "$OUTPUT_DIR"
trap - EXIT

if [[ "$INIT_GIT" -eq 1 ]]; then
  if [[ ! -d "${OUTPUT_DIR}/.git" ]]; then
    git -C "$OUTPUT_DIR" init -q
    git -C "$OUTPUT_DIR" checkout -q -b main
  fi
fi

log "public repo exported: ${OUTPUT_DIR}"
log "next steps:"
log "  1) cd ${OUTPUT_DIR}"
log "  2) git add -A && git commit -m 'docs: publish sanitized deployment architecture'"
log "  3) git remote add origin <public_repo_url> && git push -u origin main"
