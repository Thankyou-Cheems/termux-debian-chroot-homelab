#!/usr/bin/env bash
set -euo pipefail

if [[ -f /opt/data/caddy/upstreams.env ]]; then
  set -a
  # shellcheck disable=SC1091
  source /opt/data/caddy/upstreams.env
  set +a
fi

exec caddy run --config /opt/data/caddy/Caddyfile --adapter caddyfile

