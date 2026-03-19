#!/usr/bin/env bash
set -euo pipefail

PROXY_URL="${1:-http://<HOST_IP>:18888}"
DOCKER_DROPIN_DIR="/etc/systemd/system/docker.service.d"
DOCKER_PROXY_FILE="${DOCKER_DROPIN_DIR}/proxy.conf"
NO_PROXY_VALUE="${NO_PROXY_VALUE:-localhost,127.0.0.1,::1,<HOST_IP>/24}"

command -v systemctl >/dev/null 2>&1 || {
  echo "ERROR: systemctl not found" >&2
  exit 1
}
[[ "${EUID:-$(id -u)}" -eq 0 ]] || {
  echo "ERROR: run as root" >&2
  exit 1
}
systemctl cat docker >/dev/null 2>&1 || {
  echo "ERROR: docker.service not found" >&2
  exit 1
}

mkdir -p "$DOCKER_DROPIN_DIR"
cat > "$DOCKER_PROXY_FILE" <<EOF
[Service]
Environment="HTTP_PROXY=${PROXY_URL}"
Environment="HTTPS_PROXY=${PROXY_URL}"
Environment="NO_PROXY=${NO_PROXY_VALUE}"
EOF

systemctl daemon-reload
systemctl restart docker
systemctl show docker --property=Environment --no-pager
