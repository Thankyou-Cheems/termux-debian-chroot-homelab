#!/usr/bin/env bash
set -euo pipefail

DOCKER_PROXY_FILE="/etc/systemd/system/docker.service.d/proxy.conf"

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

rm -f "$DOCKER_PROXY_FILE"

systemctl daemon-reload
systemctl restart docker
systemctl show docker --property=Environment --no-pager
