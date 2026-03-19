#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-v2.62.1}"
INSTALL_ROOT="${INSTALL_ROOT:-/opt/apps/filebrowser}"
BIN_DIR="${INSTALL_ROOT}/bin"
TMP_DIR="$(mktemp -d)"
ARCH="$(uname -m)"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

case "$ARCH" in
  aarch64|arm64)
    asset_arch="arm64"
    ;;
  x86_64|amd64)
    asset_arch="amd64"
    ;;
  *)
    echo "ERROR: unsupported architecture: $ARCH" >&2
    exit 1
    ;;
esac

asset_name="linux-${asset_arch}-filebrowser.tar.gz"
base_url="https://github.com/filebrowser/filebrowser/releases/download/${VERSION}"
asset_url="${base_url}/${asset_name}"
checksums_url="${base_url}/filebrowser_${VERSION#v}_checksums.txt"

mkdir -p "$BIN_DIR"

curl -fsSL "$checksums_url" -o "${TMP_DIR}/checksums.txt"
expected_sha="$(awk -v name="$asset_name" '$2 == name { print $1; exit }' "${TMP_DIR}/checksums.txt")"
if [[ -z "$expected_sha" ]]; then
  echo "ERROR: checksum not found for ${asset_name}" >&2
  exit 1
fi

curl -fsSL "$asset_url" -o "${TMP_DIR}/${asset_name}"
actual_sha="$(sha256sum "${TMP_DIR}/${asset_name}" | awk '{print $1}')"
if [[ "$actual_sha" != "$expected_sha" ]]; then
  echo "ERROR: checksum mismatch for ${asset_name}" >&2
  exit 1
fi

tar -xzf "${TMP_DIR}/${asset_name}" -C "$TMP_DIR"
install -m 0755 "${TMP_DIR}/filebrowser" "${BIN_DIR}/filebrowser"
printf '%s\n' "$VERSION" > "${INSTALL_ROOT}/VERSION"

echo "Installed filebrowser ${VERSION} to ${BIN_DIR}/filebrowser"
